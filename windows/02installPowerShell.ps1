<#
.SYNOPSIS
    独立安装或验证 PowerShell 7。

.PARAMETER NetworkMode
    Direct、China 或 Auto。

.PARAMETER MsiPath
    可选本地签名 PowerShell MSI。

.PARAMETER Unattended
    允许本次调用出现一次 UAC。

.PARAMETER NonInteractive
    严格零提示；需要提升时返回 Blocked/10。

.OUTPUTS
    文本组件结果；失败退出 1，Blocked 退出 10。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Direct', 'China', 'Auto')]
    [string]$NetworkMode = 'Direct',

    [string]$MsiPath = '',

    [switch]$Unattended,

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Unattended -and $NonInteractive) {
    [Console]::Error.WriteLine('Unattended 与 NonInteractive 不能同时使用')
    exit 2
}
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$modulePath = Join-Path $repoRoot 'windows/bootstrap/WindowsBootstrap.psm1'
Import-Module $modulePath -Force
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    [Console]::Error.WriteLine('PowerShell 安装入口只能在 Windows 执行')
    exit 10
}
if (Test-WindowsBootstrapAdministrator) {
    [Console]::Error.WriteLine('请从普通用户进程运行 02，由隔离 helper 请求提升')
    exit 10
}

$catalog = Import-WindowsBootstrapCatalog -Path (Join-Path $repoRoot 'config/install/windows-packages.psd1')
$resolution = Resolve-WindowsBootstrapInstallOperation `
    -Name PowerShell `
    -PackageConfig $catalog.Packages.PowerShell `
    -LocalInstallerPath $MsiPath `
    -NetworkMode $NetworkMode `
    -DownloadDirectory (Join-Path $env:TEMP 'powershellScripts-bootstrap-downloads') `
    -Preview:$WhatIfPreference
Write-Output ('[{0}] PowerShell: {1}' -f $resolution.Result.Status, $resolution.Result.Message)
if ($resolution.Result.Status -eq 'Failed') { exit 1 }
if ($resolution.Result.Status -eq 'Blocked') { exit 10 }
if ($null -eq $resolution.Operation -or $WhatIfPreference) { exit 0 }
if ($NonInteractive) {
    [Console]::Error.WriteLine('严格非交互模式无法请求 PowerShell 安装提升')
    exit 10
}
$elevated = Invoke-WindowsBootstrapElevation `
    -Operation @($resolution.Operation) `
    -NetworkMode $NetworkMode `
    -ExecutorPath (Join-Path $repoRoot 'windows/bootstrap/Invoke-WindowsElevatedPlan.ps1') `
    -SourceHelperPath (Join-Path $repoRoot 'scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1') `
    -SourceConfigPath (Join-Path $repoRoot 'config/network/package-sources.bootstrap.env')
foreach ($result in @($elevated.Results)) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
if ([int]$elevated.ExitCode -ne 0) {
    exit ([int]$elevated.ExitCode)
}
$null = Update-WindowsBootstrapPath
if (-not (Test-WindowsBootstrapComponentAvailable -Name PowerShell)) {
    [Console]::Error.WriteLine('安装后仍无法发现 PowerShell 7')
    exit 10
}
exit 0
