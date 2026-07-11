#!/usr/bin/env pwsh

<#
.SYNOPSIS
    安装 Linux Full 预设的高级终端 CLI。

.PARAMETER Preset
    仅接受 Full，避免把高级 CLI 加入默认 Core。

.PARAMETER Unattended
    无人值守模式标记，由根编排器透传。

.PARAMETER NonInteractive
    严格非交互模式标记，由根编排器透传。

.OUTPUTS
    文本逐项结果；本任务不安装 Linux GUI 应用。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Full')]
    [string]$Preset = 'Full',

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
    [Console]::Error.WriteLine("当前平台不支持 Full CLI 自动安装: $($platform.DistributionId)/$($platform.Architecture)")
    exit 10
}

$results = @(Invoke-LinuxBrewCatalogInstall `
        -RepoRoot $repoRoot `
        -RequiredTag @('cli', 'terminal-extras') `
        -Preview:$WhatIfPreference)
foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
exit (Get-LinuxInstallExitCode -Result $results)
