#!/usr/bin/env pwsh

<#
.SYNOPSIS
    兼容旧 Linux 应用入口并转发到 Core CLI 叶子。

.PARAMETER Unattended
    透传无人值守模式。

.PARAMETER NonInteractive
    透传严格非交互模式。

.OUTPUTS
    新 Core CLI 叶子的文本结果和退出码。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Unattended,

    [switch]$NonInteractive
)

$targetPath = Join-Path $PSScriptRoot '05installCoreCli.ps1'
Write-Warning 'linux/04installApps.ps1 已弃用，请改用根 install.ps1 -Preset Core 或 linux/05installCoreCli.ps1'
$parameters = @{
    Preset         = 'Core'
    Unattended     = $Unattended
    NonInteractive = $NonInteractive
}
if ($WhatIfPreference) {
    $parameters.WhatIf = $true
}
& $targetPath @parameters
exit $LASTEXITCODE
