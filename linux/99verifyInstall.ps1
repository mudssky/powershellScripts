#!/usr/bin/env pwsh

<#
.SYNOPSIS
    只读验证 Linux/WSL Core 或 Full 安装状态。

.PARAMETER Preset
    Core 或 Full。

.PARAMETER Step
    可选单个或多个逻辑检查步骤。

.PARAMETER OutputFormat
    Text 或 Json。

.PARAMETER WslConfigTargetPath
    WSL 客体配置路径，测试可传临时路径。

.OUTPUTS
    文本汇总或单文档 JSON；Fail 退出 1，Blocked 退出 10。
#>
[CmdletBinding()]
param(
    [ValidateSet('Core', 'Full')]
    [string]$Preset = 'Core',

    [string[]]$Step,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [string]$WslConfigTargetPath = '/etc/wsl.conf'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$helperPath = Join-Path $repoRoot 'linux/pwsh/Test-InstallState.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    [Console]::Error.WriteLine("Linux 验证 helper 不存在: $helperPath")
    exit 1
}

$coreSteps = @('platform', 'repo', 'package-manager', 'pwsh', 'sources', 'shell', 'core-cli', 'fonts', 'profile-tools', 'docker', 'wsl-config')
$validSteps = $coreSteps + @('full-apps')
$selectedSteps = @($Step | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($selectedSteps.Count -eq 0) {
    $selectedSteps = if ($Preset -eq 'Full') { $validSteps } else { $coreSteps }
}
$unknownSteps = @($selectedSteps | Where-Object { $_ -notin $validSteps })
if ($unknownSteps.Count -gt 0) {
    [Console]::Error.WriteLine("未知 Linux 验证步骤: $($unknownSteps -join ', ')")
    exit 2
}
if ($Preset -eq 'Core' -and 'full-apps' -in $selectedSteps) {
    [Console]::Error.WriteLine('full-apps 不属于 Core 预设')
    exit 2
}

try {
    $results = @(& $helperPath `
            -Step $selectedSteps `
            -Preset $Preset `
            -OutputFormat Object `
            -WslConfigTargetPath $WslConfigTargetPath)
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

$counts = [ordered]@{
    Passed  = @($results | Where-Object Status -eq 'Pass').Count
    Warned  = @($results | Where-Object Status -eq 'Warn').Count
    Failed  = @($results | Where-Object Status -eq 'Fail').Count
    Blocked = @($results | Where-Object Status -eq 'Blocked').Count
    Skipped = @($results | Where-Object Status -eq 'Skipped').Count
}
$exitCode = if ($counts.Failed -gt 0) { 1 } elseif ($counts.Blocked -gt 0) { 10 } else { 0 }
$status = if ($exitCode -eq 1) { 'Failed' } elseif ($exitCode -eq 10) { 'Blocked' } else { 'Succeeded' }
$platformResult = $results | Where-Object Step -eq 'platform' | Select-Object -First 1
$document = [pscustomobject]@{
    SchemaVersion = 1
    Preset        = $Preset
    Environment   = if ($platformResult) { $platformResult.Name } else { '' }
    Status        = $status
    ExitCode      = $exitCode
    Counts        = $counts
    Results       = $results
}

if ($OutputFormat -eq 'Json') {
    [Console]::Out.WriteLine(($document | ConvertTo-Json -Depth 12 -Compress))
}
else {
    foreach ($result in $results) {
        Write-Output ('[{0}] {1}/{2}: {3}' -f $result.Status, $result.Step, $result.Name, $result.Message)
    }
    Write-Output ('SUMMARY pass={0} warn={1} fail={2} blocked={3} skipped={4}' -f $counts.Passed, $counts.Warned, $counts.Failed, $counts.Blocked, $counts.Skipped)
}
exit $exitCode
