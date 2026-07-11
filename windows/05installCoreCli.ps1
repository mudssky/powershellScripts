<#
.SYNOPSIS
    安装 Windows Core 预设的 Scoop CLI。

.PARAMETER Preset
    Core 或 Full；两者都包含 Core CLI。

.PARAMETER Unattended
    接受根编排器交互参数。

.PARAMETER NonInteractive
    接受根编排器交互参数。

.OUTPUTS
    文本逐项结果；失败退出 1，缺少前置退出 10。
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
Import-Module (Join-Path $repoRoot 'windows/pwsh/WindowsInstall.psm1') -Force
$platform = Get-WindowsInstallEnvironment
if (-not $WhatIfPreference -and ($platform.SupportLevel -ne 'Full' -or $platform.IsServer)) {
    [Console]::Error.WriteLine("当前平台不支持 Core CLI 自动安装: $($platform.Edition)/$($platform.Architecture)")
    exit 10
}
$results = @(Invoke-WindowsScoopCatalogInstall `
        -RepoRoot $repoRoot `
        -RequiredTag @('core', 'cli') `
        -Preview:$WhatIfPreference)
foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
exit (Get-WindowsInstallExitCode -Result $results)
