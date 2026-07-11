<#
.SYNOPSIS
    安装 Windows Profile、仓库工具并持久化用户 PATH。

.PARAMETER Preset
    Core 或 Full。

.PARAMETER Unattended
    接受根编排器交互参数。

.PARAMETER NonInteractive
    接受根编排器交互参数。

.OUTPUTS
    文本组件结果；失败退出 1，Blocked 退出 10。
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
Import-Module (Join-Path $repoRoot 'scripts/pwsh/install/ProfileTools.psm1') -Force
$platform = Get-WindowsInstallEnvironment
if (-not $WhatIfPreference -and $platform.SupportLevel -ne 'Full') {
    [Console]::Error.WriteLine("当前平台不支持完整 Profile Tools: $($platform.Edition)/$($platform.Architecture)")
    exit 10
}
if ($platform.IsAdministrator) {
    [Console]::Error.WriteLine('Profile、bin 和用户 PATH 必须由普通用户进程配置')
    exit 10
}

$results = [System.Collections.Generic.List[object]]::new()
foreach ($result in @(Invoke-ProfileToolsInstall -RepoRoot $repoRoot -Platform Windows -WhatIf:$WhatIfPreference)) {
    $results.Add($result)
}
foreach ($path in @($repoRoot, (Join-Path $repoRoot 'bin'))) {
    $results.Add((Add-WindowsUserPathEntry -Path $path -Preview:$WhatIfPreference))
}
foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
$profileExitCode = Get-ProfileToolsExitCode -Result $results.ToArray()
$windowsExitCode = Get-WindowsInstallExitCode -Result $results.ToArray()
exit $(if ($profileExitCode -eq 1 -or $windowsExitCode -eq 1) { 1 } elseif ($profileExitCode -eq 10 -or $windowsExitCode -eq 10) { 10 } else { 0 })
