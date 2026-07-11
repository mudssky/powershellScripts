#!/usr/bin/env pwsh

<#
.SYNOPSIS
    安装 macOS Full 预设的 GUI 应用和平台依赖。

.PARAMETER Preset
    仅接受 Full，避免把 Full 应用误加入默认 Core 流程。

.PARAMETER ConfigPath
    应用清单路径。

.PARAMETER Unattended
    无人值守模式标记，由根编排器透传。

.PARAMETER NonInteractive
    严格非交互模式标记，由根编排器透传。

.OUTPUTS
    文本逐项结果；存在 required failure 时退出 1。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Full')]
    [string]$Preset = 'Full',

    [string]$ConfigPath = '',

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
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repoRoot 'profile/installer/apps-config.json'
}
Import-Module (Join-Path $repoRoot 'psutils') -Force

$config = (Resolve-ConfigSources -Sources @(
        @{ Type = 'JsonFile'; Name = 'AppsConfig'; Path = $ConfigPath }
    ) -BasePath $repoRoot -ErrorOnMissing).Values
$null = Test-PackageManagerAppCatalog -ConfigObject $config
$results = @(Install-PackageManagerApps `
        -PackageManager homebrew `
        -ConfigObject $config `
        -TargetOS macOS `
        -RequiredTag @('full') `
        -AnyTag @('gui', 'platform') `
        -Required `
        -WhatIf:$WhatIfPreference)

foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
if ($results.Count -eq 0 -or @($results | Where-Object { $_.Required -and $_.Status -eq 'Failed' }).Count -gt 0) {
    exit 1
}
exit 0
