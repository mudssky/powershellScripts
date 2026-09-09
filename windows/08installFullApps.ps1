<#
.SYNOPSIS
    安装 Windows Full 预设的高级终端 CLI。

.PARAMETER Preset
    仅接受 Full。

.PARAMETER Unattended
    接受根编排器交互参数。

.PARAMETER NonInteractive
    接受根编排器交互参数。

.OUTPUTS
    文本逐项结果；失败退出 1，缺少前置退出 10。
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
Import-Module (Join-Path $repoRoot 'windows/pwsh/WindowsInstall.psm1') -Force
$platform = Get-WindowsInstallEnvironment
if (-not $WhatIfPreference -and ($platform.SupportLevel -ne 'Full' -or $platform.IsServer)) {
    [Console]::Error.WriteLine("当前平台不支持 Full CLI 自动安装: $($platform.Edition)/$($platform.Architecture)")
    exit 10
}
$results = @(Invoke-WindowsScoopCatalogInstall `
        -RepoRoot $repoRoot `
        -RequiredTag @('cli', 'terminal-extras') `
        -Preview:$WhatIfPreference)
# Full 预设还包含 WinGet 段应用（AutoHotkey 与 SSHCopyID）；AutoHotkey 与 09 的
# 安装通过已安装检测天然幂等，eartrumpet（skipInstall、无标签）不进入安装选择。
$wingetResults = @(Invoke-WindowsWingetCatalogInstall `
        -RepoRoot $repoRoot `
        -RequiredTag @('full', 'platform') `
        -Preview:$WhatIfPreference)
$results = @($results) + @($wingetResults)
foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
exit (Get-WindowsInstallExitCode -Result $results)
