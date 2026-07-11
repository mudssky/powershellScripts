Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AdapterSupport.psm1') -Force

function Get-ManagedEnvPackageSourcePath {
    <#
    .SYNOPSIS
        返回 package source 受管环境变量文件路径。

    .OUTPUTS
        string。当前用户的受管 env 文件路径。
    #>
    [CmdletBinding()]
    param()

    $configRoot = [Environment]::GetEnvironmentVariable('XDG_CONFIG_HOME', 'Process')
    if ([string]::IsNullOrWhiteSpace($configRoot)) {
        $homePath = [Environment]::GetEnvironmentVariable('HOME', 'Process')
        if ([string]::IsNullOrWhiteSpace($homePath)) {
            $homePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        }
        $configRoot = Join-Path $homePath '.config'
    }

    return Join-Path $configRoot 'powershellScripts/package-sources.env'
}

function ConvertFrom-ManagedEnvExports {
    <#
    .SYNOPSIS
        从 chsrc 隔离输出中提取白名单环境变量。

    .PARAMETER Content
        隔离 shell rc 的完整内容。

    .PARAMETER AllowedName
        允许写入受管 env 的变量名。

    .OUTPUTS
        hashtable。变量名到 HTTPS URL 的映射。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$AllowedName
    )

    $allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($name in $AllowedName) {
        $null = $allowed.Add($name)
    }

    $values = @{}
    $pattern = '(?m)^\s*export\s+(?<name>[A-Z][A-Z0-9_]*)="(?<value>[^"\r\n]+)"\s*$'
    foreach ($match in [regex]::Matches($Content, $pattern)) {
        $name = $match.Groups['name'].Value
        if (-not $allowed.Contains($name)) {
            continue
        }

        $value = $match.Groups['value'].Value
        $uri = $null
        if (-not [uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
            throw "chsrc 生成了非 HTTPS 环境变量: $name"
        }
        $values[$name] = $value
    }

    foreach ($name in $AllowedName) {
        if (-not $values.ContainsKey($name)) {
            throw "chsrc 隔离输出缺少环境变量: $name"
        }
    }

    return $values
}

function Set-ManagedEnvTargetBlock {
    <#
    .SYNOPSIS
        更新受管 env 文件中的单个 target block。

    .DESCRIPTION
        只替换本仓库拥有的 marker block，保留文件中其它 target 或人工内容。
        真实变化时才创建可读时间戳备份并执行原子写入。

    .PARAMETER Path
        受管 env 文件路径。

    .PARAMETER Target
        target 名称。

    .PARAMETER EnvironmentName
        环境变量输出顺序。

    .PARAMETER Values
        环境变量值。

    .OUTPUTS
        PSCustomObject。包含 Path、Changed 与 Source。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [string[]]$EnvironmentName,

        [Parameter(Mandatory)]
        [hashtable]$Values
    )

    $beginMarker = "# powershellScripts package source: $Target begin"
    $endMarker = "# powershellScripts package source: $Target end"
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($beginMarker)
    foreach ($name in $EnvironmentName) {
        $lines.Add(('export {0}="{1}"' -f $name, $Values[$name]))
    }
    $lines.Add($endMarker)
    $block = $lines -join [Environment]::NewLine

    $current = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Get-Content -LiteralPath $Path -Raw -Encoding utf8
    }
    else {
        ''
    }
    $pattern = '(?ms)^' + [regex]::Escape($beginMarker) + '.*?^' + [regex]::Escape($endMarker) + '\r?\n?'
    $remaining = [regex]::Replace($current, $pattern, '').TrimEnd()
    $next = if ([string]::IsNullOrWhiteSpace($remaining)) {
        $block + [Environment]::NewLine
    }
    else {
        $remaining + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine
    }

    if ($current -ceq $next) {
        return [PSCustomObject]@{
            Path    = $Path
            Changed = $false
            Source  = $Values[$EnvironmentName[0]]
        }
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $backupPath = '{0}.{1}.bak' -f $Path, (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff')
        Copy-Item -LiteralPath $Path -Destination $backupPath
        Set-PackageSourceFileMode -Path $backupPath -Mode ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
    }

    $null = Write-PackageSourceTextAtomic -Path $Path -Value $next
    Set-PackageSourceFileMode -Path $Path -Mode ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
    return [PSCustomObject]@{
        Path    = $Path
        Changed = $true
        Source  = $Values[$EnvironmentName[0]]
    }
}

function Invoke-ManagedEnvPackageSourceApply {
    <#
    .SYNOPSIS
        通过隔离 HOME 运行 chsrc，并写入仓库受管 env 文件。

    .DESCRIPTION
        chsrc 只能修改临时 shell rc；adapter 从中提取 catalog 白名单变量并校验 HTTPS，
        因而不会直接改写用户的 zshrc 或 bashrc。

    .PARAMETER Target
        package source target。

    .PARAMETER TargetConfig
        catalog 中该 target 的配置。

    .PARAMETER MinimumChsrcVersion
        允许的最低 chsrc 版本。

    .PARAMETER Selection
        Auto、First 或指定 provider。

    .OUTPUTS
        PSCustomObject。包含 Path、Changed、Source 与 ChsrcVersion。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [hashtable]$TargetConfig,

        [Parameter(Mandatory)]
        [version]$MinimumChsrcVersion,

        [string]$Selection = 'Auto'
    )

    if ($IsWindows) {
        throw 'managed-env shell adapter 暂不支持原生 Windows'
    }

    $chsrcPath = Resolve-ChsrcExecutablePath
    $chsrcVersion = Assert-ChsrcVersion -FilePath $chsrcPath -MinimumVersion $MinimumChsrcVersion
    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('package-source-chsrc-{0}' -f [guid]::NewGuid().ToString('N'))
    $stagingHome = Join-Path $stagingRoot 'home'
    New-Item -ItemType Directory -Path $stagingHome -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $stagingHome '.zshrc') -Value '' -Encoding utf8NoBOM

    try {
        $arguments = [System.Collections.Generic.List[string]]::new()
        foreach ($argument in @('set', '-no-color', '-scope=user', [string]$TargetConfig.chsrc_target)) {
            $arguments.Add($argument)
        }
        if ($Selection -eq 'First') {
            $arguments.Add('first')
        }
        elseif ($Selection -ne 'Auto') {
            $arguments.Add($Selection)
        }

        $processResult = Invoke-PackageSourceProcess -FilePath $chsrcPath -ArgumentList $arguments.ToArray() -Environment @{
            HOME            = $stagingHome
            USERPROFILE     = $stagingHome
            XDG_CONFIG_HOME = (Join-Path $stagingHome '.config')
            SHELL           = '/bin/zsh'
        }
        if ($processResult.ExitCode -ne 0) {
            throw "chsrc managed-env 执行失败: $($processResult.StdErr.Trim())"
        }

        $generatedContent = Get-Content -LiteralPath (Join-Path $stagingHome '.zshrc') -Raw -Encoding utf8
        $environmentNames = @($TargetConfig.managed_environment | ForEach-Object { [string]$_ })
        $values = ConvertFrom-ManagedEnvExports -Content $generatedContent -AllowedName $environmentNames
        $managedPath = Get-ManagedEnvPackageSourcePath
        $result = Set-ManagedEnvTargetBlock -Path $managedPath -Target $Target -EnvironmentName $environmentNames -Values $values
        $result | Add-Member -NotePropertyName ChsrcVersion -NotePropertyValue ([string]$chsrcVersion)
        return $result
    }
    finally {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-ManagedEnvPackageSourceState {
    <#
    .SYNOPSIS
        从当前进程读取 managed-env target 的现有 source。

    .PARAMETER TargetConfig
        catalog 中该 target 的配置。

    .OUTPUTS
        PSCustomObject 或 null。包含安全展示的 Source。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TargetConfig
    )

    foreach ($name in @($TargetConfig.managed_environment)) {
        $value = [Environment]::GetEnvironmentVariable([string]$name, 'Process')
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return [PSCustomObject]@{
                Source = ConvertTo-SafePackageSourceUrl -Value $value
            }
        }
    }
    return $null
}

Export-ModuleMember -Function @(
    'Get-ManagedEnvPackageSourcePath'
    'Get-ManagedEnvPackageSourceState'
    'Invoke-ManagedEnvPackageSourceApply'
)
