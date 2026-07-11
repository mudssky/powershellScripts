#!/usr/bin/env pwsh

<#
.SYNOPSIS
    安装 Linux Profile、仓库工具、Docker 与 WSL 客体配置。

.PARAMETER Preset
    Core 或 Full；两者共享本步骤。

.PARAMETER WslConfigSourcePath
    WSL 客体配置模板路径，默认使用仓库模板。

.PARAMETER WslConfigTargetPath
    WSL 客体目标路径，生产默认 `/etc/wsl.conf`，测试可传临时路径。

.PARAMETER Unattended
    无人值守模式，执行写操作前允许一次 sudo 认证。

.PARAMETER NonInteractive
    严格非交互模式，sudo 前置不足时返回 Blocked。

.OUTPUTS
    文本组件结果；失败退出 1，Blocked 或需要 WSL 重启时退出 10。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Core', 'Full')]
    [string]$Preset = 'Core',

    [string]$WslConfigSourcePath = '',

    [string]$WslConfigTargetPath = '/etc/wsl.conf',

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
if ([string]::IsNullOrWhiteSpace($WslConfigSourcePath)) {
    $WslConfigSourcePath = Join-Path $repoRoot 'linux/wsl/wsl.conf'
}
Import-Module (Join-Path $repoRoot 'linux/pwsh/LinuxInstall.psm1') -Force
Import-Module (Join-Path $repoRoot 'scripts/pwsh/install/ProfileTools.psm1') -Force

$platform = Get-LinuxInstallEnvironment
if ($platform.SupportLevel -ne 'Full') {
    [Console]::Error.WriteLine("当前平台不支持完整 Profile Tools: $($platform.DistributionId)/$($platform.Architecture)")
    exit 10
}

$results = [System.Collections.Generic.List[object]]::new()
$sudoPreflight = Get-LinuxSudoPreflightResult `
    -Unattended:$Unattended `
    -NonInteractive:$NonInteractive `
    -Preview:$WhatIfPreference
if ($sudoPreflight) {
    $results.Add($sudoPreflight)
}

if (@($results | Where-Object Status -eq 'Blocked').Count -gt 0) {
    foreach ($result in $results) {
        Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
    }
    exit 10
}

$catalog = Import-LinuxPackageCatalog -Path (Join-Path $repoRoot 'config/install/linux-packages.psd1')
$family = Get-LinuxPackageFamily -Catalog $catalog -DistributionFamily $platform.DistributionFamily
foreach ($result in @(Install-LinuxSystemPackages -DistributionFamily $platform.DistributionFamily -Name core-system -Package @($family.CoreSystem) -Update -Preview:$WhatIfPreference)) {
    $results.Add($result)
}

foreach ($result in @(Invoke-ProfileToolsInstall -RepoRoot $repoRoot -Platform Linux -WhatIf:$WhatIfPreference)) {
    $results.Add($result)
}

$wslConfigResult = $null
if ($platform.IsWsl) {
    $wslConfigResult = Install-WslGuestConfig `
        -SourcePath $WslConfigSourcePath `
        -TargetPath $WslConfigTargetPath `
        -Preview:$WhatIfPreference
    $results.Add($wslConfigResult)
}

if ($wslConfigResult -and $wslConfigResult.Status -eq 'RestartRequired') {
    $results.Add((New-LinuxInstallResult -Name docker -Status Blocked -Message 'WSL 配置已变化，宿主重启后再安装 Docker Engine' -ExitCode 10))
}
elseif (@($results | Where-Object { $_.Status -in @('Failed', 'Blocked') }).Count -eq 0) {
    foreach ($result in @(Install-LinuxDocker -Platform $platform -PackageFamily $family -Preview:$WhatIfPreference)) {
        $results.Add($result)
    }
}

foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
exit (Get-LinuxInstallExitCode -Result $results)
