Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AdapterSupport.psm1') -Force

function Resolve-ChsrcSystemResourcePath {
    <#
    .SYNOPSIS
        将 catalog 系统路径映射到真实系统根或测试根。

    .PARAMETER Path
        catalog 中的绝对 Unix 路径。

    .OUTPUTS
        string。实际读取和 snapshot 的路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $testRoot = [Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT', 'Process')
    if ([string]::IsNullOrWhiteSpace($testRoot)) {
        return $Path
    }

    return Join-Path $testRoot $Path.TrimStart('/', '\')
}

function Get-ChsrcSystemPackageSourceResourcePath {
    <#
    .SYNOPSIS
        返回系统 source target 可能修改的文件。

    .PARAMETER TargetConfig
        catalog 中该 target 的配置。

    .OUTPUTS
        string[]。映射后的系统 source 文件路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TargetConfig
    )

    return @($TargetConfig.resource_paths | ForEach-Object {
            Resolve-ChsrcSystemResourcePath -Path ([string]$_)
        })
}

function Assert-ChsrcSystemPackageSourcePrivilege {
    <#
    .SYNOPSIS
        验证真实系统 source 修改具有 root 权限。

    .DESCRIPTION
        设置测试系统根时跳过权限检查；真实执行只允许 Linux root。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT', 'Process'))) {
        return
    }
    if (-not $IsLinux) {
        throw (New-PackageSourceAdapterException -Message '系统 package source adapter 只支持 Linux' -ExitCode 10 -Code 'Blocked')
    }

    $idCommand = Get-Command id -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $idCommand) {
        throw (New-PackageSourceAdapterException -Message '无法验证当前 Linux 用户权限' -ExitCode 10 -Code 'Blocked')
    }
    $result = Invoke-PackageSourceProcess -FilePath $idCommand.Source -ArgumentList @('-u')
    if ($result.ExitCode -ne 0 -or $result.StdOut.Trim() -ne '0') {
        throw (New-PackageSourceAdapterException -Message '系统 package source 修改需要 sudo/root' -ExitCode 10 -Code 'Blocked')
    }
}

function Invoke-ChsrcSystemPackageSourceApply {
    <#
    .SYNOPSIS
        使用 chsrc system scope 修改 Linux 系统 source。

    .PARAMETER Target
        debian、ubuntu 或 arch。

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
        [ValidateSet('debian', 'ubuntu', 'arch')]
        [string]$Target,

        [Parameter(Mandatory)]
        [hashtable]$TargetConfig,

        [Parameter(Mandatory)]
        [version]$MinimumChsrcVersion,

        [string]$Selection = 'Auto'
    )

    Assert-ChsrcSystemPackageSourcePrivilege
    $resourcePaths = @(Get-ChsrcSystemPackageSourceResourcePath -TargetConfig $TargetConfig)
    $beforeHashes = @{}
    foreach ($path in $resourcePaths) {
        $beforeHashes[$path] = Get-PackageSourceFileHash -Path $path
    }

    $chsrcPath = Resolve-ChsrcExecutablePath
    $chsrcVersion = Assert-ChsrcVersion -FilePath $chsrcPath -MinimumVersion $MinimumChsrcVersion
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @('set', '-no-color', '-scope=system', [string]$TargetConfig.chsrc_target)) {
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
        throw (New-PackageSourceAdapterException -Message "chsrc system target 执行失败: $($result.StdErr.Trim())" -ExitCode 10 -Code 'Blocked')
    }

    $changed = $false
    $source = ''
    foreach ($path in $resourcePaths) {
        if ((Get-PackageSourceFileHash -Path $path) -ne [string]$beforeHashes[$path]) {
            $changed = $true
        }
        if ([string]::IsNullOrWhiteSpace($source) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            $match = [regex]::Match((Get-Content -LiteralPath $path -Raw -Encoding utf8), 'https://[^\s"'']+')
            if ($match.Success) {
                $source = ConvertTo-SafePackageSourceUrl -Value $match.Value
            }
        }
    }
    if (-not $changed) {
        throw (New-PackageSourceAdapterException -Message "chsrc 未修改任何已声明的 $Target source 文件" -ExitCode 10 -Code 'Blocked')
    }

    return [PSCustomObject]@{
        Source       = $source
        Changed      = $true
        ChsrcVersion = [string]$chsrcVersion
    }
}

Export-ModuleMember -Function @(
    'Get-ChsrcSystemPackageSourceResourcePath'
    'Invoke-ChsrcSystemPackageSourceApply'
)
