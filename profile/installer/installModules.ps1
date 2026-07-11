#!/usr/bin/env pwsh

<#
.SYNOPSIS
    按平台安装 PowerShell Profile 所需模块。

.PARAMETER Platform
    Auto、Windows、macOS 或 Linux。

.OUTPUTS
    PSCustomObject[]。逐模块安装结果。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Auto', 'Windows', 'macOS', 'Linux')]
    [string]$Platform = 'Auto'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not (Get-Command Install-RequiredModule -ErrorAction SilentlyContinue)) {
    Import-Module (Join-Path $repoRoot 'psutils') -Force
}

if ($Platform -eq 'Auto') {
    $Platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux' }
}

$requiredModules = [System.Collections.Generic.List[string]]::new()
$requiredModules.Add('Pester')
$requiredModules.Add('PSReadLine')
if ($Platform -eq 'Windows') {
    $requiredModules.Add('BurntToast')
}

Install-RequiredModule -ModuleNames $requiredModules.ToArray() -WhatIf:$WhatIfPreference
