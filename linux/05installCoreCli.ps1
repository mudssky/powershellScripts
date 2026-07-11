#!/usr/bin/env pwsh

<#
.SYNOPSIS
    安装 Linux Core 预设的跨平台 CLI。

.PARAMETER Preset
    Core 或 Full；两者都包含 Core CLI。

.PARAMETER Unattended
    无人值守模式标记，由根编排器透传。

.PARAMETER NonInteractive
    严格非交互模式标记，由根编排器透传。

.OUTPUTS
    文本逐项结果；失败退出 1，前置不足退出 10。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Core', 'Full')]
    [string]$Preset = 'Core',

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
if ($platform.Architecture -ne 'amd64' -or $platform.DistributionFamily -eq 'unknown') {
    [Console]::Error.WriteLine("当前平台不支持 Core CLI 自动安装: $($platform.DistributionId)/$($platform.Architecture)")
    exit 10
}

$results = @(Invoke-LinuxBrewCatalogInstall `
        -RepoRoot $repoRoot `
        -RequiredTag @('core', 'cli') `
        -Preview:$WhatIfPreference)
foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
exit (Get-LinuxInstallExitCode -Result $results)
