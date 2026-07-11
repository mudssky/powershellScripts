#!/usr/bin/env pwsh

<#
.SYNOPSIS
    按 Linux 环境能力安装桌面字体。

.PARAMETER Preset
    Core 或 Full；两者共享字体步骤。

.PARAMETER Environment
    Auto、Desktop 或 Server。Auto 在 WSL 和无桌面环境中选择 Server。

.PARAMETER Unattended
    无人值守模式标记，由根编排器透传。

.PARAMETER NonInteractive
    严格非交互模式标记，由根编排器透传。

.OUTPUTS
    文本组件结果；服务器/WSL 默认输出 Skipped 并退出 0。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Core', 'Full')]
    [string]$Preset = 'Core',

    [ValidateSet('Auto', 'Desktop', 'Server')]
    [string]$Environment = 'Auto',

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
Import-Module (Join-Path $repoRoot 'linux/pwsh/LinuxInstall.psm1') -Force
$platform = Get-LinuxInstallEnvironment
if ($platform.Architecture -ne 'amd64' -or $platform.DistributionFamily -notin @('debian', 'arch')) {
    [Console]::Error.WriteLine("当前平台不支持字体自动安装: $($platform.DistributionId)/$($platform.Architecture)")
    exit 10
}

$effectiveEnvironment = Resolve-LinuxFontEnvironment -Environment $Environment -Platform $platform
if ($effectiveEnvironment -eq 'Server') {
    Write-Output '[Skipped] fonts: Server/WSL 环境默认不安装 Linux 字体'
    exit 0
}

$catalog = Import-LinuxPackageCatalog -Path (Join-Path $repoRoot 'config/install/linux-packages.psd1')
$family = Get-LinuxPackageFamily -Catalog $catalog -DistributionFamily $platform.DistributionFamily
$packages = @($family.DesktopFonts.Required)
if (-not $WhatIfPreference) {
    foreach ($optionalPackage in @($family.DesktopFonts.Optional)) {
        $candidate = Resolve-LinuxPackageAlternative -DistributionFamily $platform.DistributionFamily -Candidate @($optionalPackage)
        if ($candidate) {
            $packages += $candidate
        }
    }
}

$results = [System.Collections.Generic.List[object]]::new()
foreach ($result in @(Install-LinuxSystemPackages -DistributionFamily $platform.DistributionFamily -Name fonts-packages -Package $packages -Update -Preview:$WhatIfPreference)) {
    $results.Add($result)
}
if (@($results | Where-Object Status -eq 'Failed').Count -eq 0) {
    $results.Add((Invoke-LinuxNativeCommand -Name font-cache -FilePath fc-cache -ArgumentList @('-f') -Preview:$WhatIfPreference))
}
foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
exit (Get-LinuxInstallExitCode -Result $results)
