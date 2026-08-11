Set-StrictMode -Version Latest

<##
.SYNOPSIS
    导入共享配置解析模块。
.OUTPUTS
    None
    幂等导入 psutils 配置解析能力。
#>
function Import-BrowserDebugConfigDependency {
    [CmdletBinding()]
    param()
    $loadedMarker = Get-Variable -Name BrowserDebugConfigDependencyLoaded -Scope Script -ErrorAction SilentlyContinue
    if ($loadedMarker -and [bool]$loadedMarker.Value) { return }
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
    $modulePath = Join-Path $repoRoot 'psutils/modules/config.psm1'
    # 依赖标记位于脚本作用域，因此模块命令也必须导入持久作用域，避免辅助函数返回后命令不可见。
    Import-Module $modulePath -Force -Global -ErrorAction Stop
    $script:BrowserDebugConfigDependencyLoaded = $true
}

<##
.SYNOPSIS
    解析默认或显式注册表路径。
.PARAMETER RegistryPath
    可选注册表覆盖路径。
.OUTPUTS
    System.String
    返回绝对注册表路径。
#>
function Resolve-BrowserDebugRegistryPath {
    [CmdletBinding()]
    param([string]$RegistryPath)

    $candidate = $RegistryPath
    if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = $env:BROWSER_DEBUG_REGISTRY_PATH }
    if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = 'D:\browser-debug-profiles\registry.json' }
    return [System.IO.Path]::GetFullPath($candidate)
}

<##
.SYNOPSIS
    创建空注册表对象。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回 schemaVersion=1 的空对象。
#>
function New-BrowserDebugRegistry {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{ schemaVersion = 1; profiles = @(); sshConfigurations = @() }
}

<##
.SYNOPSIS
    读取 browser-debug 注册表。
.PARAMETER RegistryPath
    注册表文件路径。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回规范化注册表对象。
#>
function Read-BrowserDebugRegistry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryPath)

    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) { return New-BrowserDebugRegistry }
    try {
        Import-BrowserDebugConfigDependency
        $registry = (Resolve-ConfigSources -Sources @(
                @{ Type = 'JsonFile'; Name = 'BrowserDebugRegistry'; Path = $RegistryPath }
            ) -ErrorOnMissing).Values
    }
    catch { throw "注册表 JSON 无效: $RegistryPath。$($_.Exception.Message)" }
    if ([int]$registry.schemaVersion -ne 1) { throw "不支持的注册表 schemaVersion: $($registry.schemaVersion)" }
    if ($null -eq $registry.profiles) { $registry['profiles'] = @() }
    if ($null -eq $registry.sshConfigurations) { $registry['sshConfigurations'] = @() }
    return $registry
}

<##
.SYNOPSIS
    备份并原子写入注册表。
.PARAMETER RegistryPath
    注册表目标路径。
.PARAMETER Registry
    要写入的注册表对象。
.OUTPUTS
    System.String
    返回写入后的注册表路径。
#>
function Write-BrowserDebugRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryPath,
        [Parameter(Mandatory)][object]$Registry
    )

    $directory = Split-Path -Parent $RegistryPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        if ($RegistryPath.StartsWith('D:\', [System.StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path 'D:\')) {
            throw '默认 D 盘不存在；请使用 --profile-path 和 --registry-path 显式指定可用位置。'
        }
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $RegistryPath -PathType Leaf) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'
        Copy-Item -LiteralPath $RegistryPath -Destination "$RegistryPath.$timestamp.bak" -Force
    }
    $tempPath = Join-Path $directory (".{0}.{1}.tmp" -f ([System.IO.Path]::GetFileName($RegistryPath)), [guid]::NewGuid().ToString('N'))
    try {
        $Registry | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $tempPath -Encoding utf8NoBOM
        [System.IO.File]::Move($tempPath, $RegistryPath, $true)
    }
    catch { throw "写入注册表失败，临时文件保留在 $tempPath。$($_.Exception.Message)" }
    return $RegistryPath
}

<##
.SYNOPSIS
    按名称查找 Profile。
.PARAMETER Registry
    注册表对象。
.PARAMETER Name
    Profile 名称。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回匹配 Profile，不存在时返回空值。
#>
function Find-BrowserDebugProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Registry, [Parameter(Mandatory)][string]$Name)
    return @($Registry.profiles | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
}

<##
.SYNOPSIS
    按名称查找 SSH 配置。
.PARAMETER Registry
    注册表对象。
.PARAMETER Name
    SSH 配置名称。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回匹配配置，不存在时返回空值。
#>
function Find-BrowserDebugSshConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Registry, [Parameter(Mandatory)][string]$Name)
    return @($Registry.sshConfigurations | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
}
