Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AdapterSupport.psm1') -Force

function Resolve-PackageSourceNativeCommand {
    <#
    .SYNOPSIS
        解析 chsrc command adapter 使用的原生工具。

    .DESCRIPTION
        测试可通过 target 专属环境变量覆盖可执行路径；生产环境从 PATH 查找。

    .PARAMETER Target
        npm、pnpm、pip 或 go。

    .OUTPUTS
        PSCustomObject。包含 FilePath 与 PrefixArguments。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('npm', 'pnpm', 'pip', 'go')]
        [string]$Target
    )

    $definitions = @{
        npm  = @{ Override = 'POWERSHELL_SCRIPTS_NPM_PATH'; Command = 'npm'; Prefix = @() }
        pnpm = @{ Override = 'POWERSHELL_SCRIPTS_PNPM_PATH'; Command = 'pnpm'; Prefix = @() }
        pip  = @{ Override = 'POWERSHELL_SCRIPTS_PYTHON_PATH'; Command = 'python3'; Prefix = @('-m', 'pip') }
        go   = @{ Override = 'POWERSHELL_SCRIPTS_GO_PATH'; Command = 'go'; Prefix = @() }
    }
    $definition = $definitions[$Target]
    $overridePath = [Environment]::GetEnvironmentVariable([string]$definition.Override, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($overridePath)) {
        if (-not (Test-Path -LiteralPath $overridePath -PathType Leaf)) {
            throw "指定的 $Target 命令不存在: $overridePath"
        }
        $filePath = [System.IO.Path]::GetFullPath($overridePath)
    }
    else {
        $command = Get-Command ([string]$definition.Command) -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $command -and $Target -eq 'pip') {
            $command = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($null -eq $command) {
            throw "未找到 $Target 命令"
        }
        $filePath = $command.Source
    }

    return [PSCustomObject]@{
        FilePath        = $filePath
        PrefixArguments = @($definition.Prefix)
    }
}

function Invoke-PackageSourceNativeCommand {
    <#
    .SYNOPSIS
        执行 target 对应的原生配置命令。

    .PARAMETER Target
        npm、pnpm、pip 或 go。

    .PARAMETER ArgumentList
        target 命令参数，不含 pip 的 python 模块前缀。

    .OUTPUTS
        PSCustomObject。包含 ExitCode、StdOut 与 StdErr。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('npm', 'pnpm', 'pip', 'go')]
        [string]$Target,

        [string[]]$ArgumentList = @()
    )

    $command = Resolve-PackageSourceNativeCommand -Target $Target
    $arguments = @($command.PrefixArguments) + @($ArgumentList)
    return Invoke-PackageSourceProcess -FilePath $command.FilePath -ArgumentList $arguments
}

function Get-ChsrcCommandPackageSourceResourcePath {
    <#
    .SYNOPSIS
        返回 chsrc command adapter 会修改的配置文件。

    .PARAMETER Target
        npm、pnpm、pip 或 go。

    .OUTPUTS
        string[]。需要在事务中 snapshot 的配置文件路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('npm', 'pnpm', 'pip', 'go')]
        [string]$Target
    )

    switch ($Target) {
        'npm' {
            $result = Invoke-PackageSourceNativeCommand -Target npm -ArgumentList @('config', 'get', 'userconfig')
            if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.StdOut)) {
                throw "无法解析 npm userconfig: $($result.StdErr.Trim())"
            }
            return @($result.StdOut.Trim())
        }
        'pnpm' {
            $result = Invoke-PackageSourceNativeCommand -Target pnpm -ArgumentList @('config', 'get', 'globalconfig')
            if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.StdOut)) {
                throw "无法解析 pnpm globalconfig: $($result.StdErr.Trim())"
            }
            return @($result.StdOut.Trim())
        }
        'pip' {
            $result = Invoke-PackageSourceNativeCommand -Target pip -ArgumentList @('config', 'debug')
            if ($result.ExitCode -ne 0) {
                throw "无法解析 pip user config: $($result.StdErr.Trim())"
            }

            $paths = [System.Collections.Generic.List[string]]::new()
            $insideUserSection = $false
            foreach ($line in ($result.StdOut -split '\r?\n')) {
                if ($line -eq 'user:') {
                    $insideUserSection = $true
                    continue
                }
                if ($insideUserSection -and $line -match '^[A-Za-z_]+:$') {
                    break
                }
                if ($insideUserSection -and $line -match '^\s{2}(?<path>.+), exists: (?:True|False)$') {
                    $paths.Add($Matches.path)
                }
            }
            if ($paths.Count -eq 0) {
                throw 'pip config debug 未返回 user 配置路径'
            }
            return $paths.ToArray()
        }
        'go' {
            $result = Invoke-PackageSourceNativeCommand -Target go -ArgumentList @('env', 'GOENV')
            if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.StdOut)) {
                throw "无法解析 go env GOENV: $($result.StdErr.Trim())"
            }
            return @($result.StdOut.Trim())
        }
    }
}

function Get-ChsrcCommandPackageSourceState {
    <#
    .SYNOPSIS
        读取 chsrc command target 当前 source。

    .PARAMETER Target
        npm、pnpm、pip 或 go。

    .OUTPUTS
        PSCustomObject。包含可安全展示的 Source。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('npm', 'pnpm', 'pip', 'go')]
        [string]$Target
    )

    $result = switch ($Target) {
        'npm' { Invoke-PackageSourceNativeCommand -Target npm -ArgumentList @('config', 'get', 'registry') }
        'pnpm' { Invoke-PackageSourceNativeCommand -Target pnpm -ArgumentList @('config', 'get', 'registry') }
        'pip' { Invoke-PackageSourceNativeCommand -Target pip -ArgumentList @('config', 'get', 'global.index-url') }
        'go' { Invoke-PackageSourceNativeCommand -Target go -ArgumentList @('env', 'GOPROXY') }
    }
    if ($result.ExitCode -ne 0) {
        if ($Target -eq 'pip') {
            return [PSCustomObject]@{ Source = 'https://pypi.org/simple/' }
        }
        throw "读取 $Target 当前 source 失败: $($result.StdErr.Trim())"
    }

    $rawSource = $result.StdOut.Trim()
    if ($Target -eq 'go') {
        $rawSource = ($rawSource -split ',')[0]
    }
    return [PSCustomObject]@{
        Source = ConvertTo-SafePackageSourceUrl -Value $rawSource
    }
}

function Invoke-ChsrcCommandPackageSourceApply {
    <#
    .SYNOPSIS
        使用 chsrc 应用 command target，并通过原生命令验证结果。

    .PARAMETER Target
        npm、pnpm、pip 或 go。

    .PARAMETER TargetConfig
        catalog 中该 target 的配置。

    .PARAMETER MinimumChsrcVersion
        允许的最低 chsrc 版本。

    .PARAMETER Selection
        Auto、First 或指定 provider。

    .OUTPUTS
        PSCustomObject。包含 Source、Changed 与 ChsrcVersion。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('npm', 'pnpm', 'pip', 'go')]
        [string]$Target,

        [Parameter(Mandatory)]
        [hashtable]$TargetConfig,

        [Parameter(Mandatory)]
        [version]$MinimumChsrcVersion,

        [string]$Selection = 'Auto'
    )

    $null = Resolve-PackageSourceNativeCommand -Target $Target
    $chsrcPath = Resolve-ChsrcExecutablePath
    $chsrcVersion = Assert-ChsrcVersion -FilePath $chsrcPath -MinimumVersion $MinimumChsrcVersion
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @('set', '-no-color', "-scope=$([string]$TargetConfig.scope)", [string]$TargetConfig.chsrc_target)) {
        $arguments.Add($argument)
    }
    if ($Selection -eq 'First') {
        $arguments.Add('first')
    }
    elseif ($Selection -ne 'Auto') {
        $arguments.Add($Selection)
    }

    $result = Invoke-PackageSourceProcess -FilePath $chsrcPath -ArgumentList $arguments.ToArray()
    if ($result.ExitCode -ne 0) {
        throw "chsrc $Target 执行失败: $($result.StdErr.Trim())"
    }

    $state = Get-ChsrcCommandPackageSourceState -Target $Target
    return [PSCustomObject]@{
        Source       = $state.Source
        Changed      = $true
        ChsrcVersion = [string]$chsrcVersion
    }
}

Export-ModuleMember -Function @(
    'Get-ChsrcCommandPackageSourceResourcePath'
    'Get-ChsrcCommandPackageSourceState'
    'Invoke-ChsrcCommandPackageSourceApply'
)
