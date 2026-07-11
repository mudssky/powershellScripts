<#
.SYNOPSIS
    只读验证 Windows Core 或 Full 安装状态。

.PARAMETER Preset
    Core 或 Full。

.PARAMETER Step
    可选单个或多个逻辑检查步骤。

.PARAMETER IncludeWsl
    将 WSL 宿主纳入强制验证。

.PARAMETER OutputFormat
    Text 或 Json。

.PARAMETER WslConfigTargetPath
    用户级 .wslconfig 路径；测试可传临时路径。

.OUTPUTS
    文本汇总或单文档 JSON；Fail 退出 1，Blocked 退出 10。
#>
[CmdletBinding()]
param(
    [ValidateSet('Core', 'Full')]
    [string]$Preset = 'Core',

    [string[]]$Step,

    [switch]$IncludeWsl,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [string]$WslConfigTargetPath = $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.wslconfig' } else { '' }),

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
$helperPath = Join-Path $repoRoot 'windows/pwsh/Test-InstallState.ps1'
$coreSteps = @('platform', 'repo', 'package-manager', 'pwsh', 'sources', 'core-cli', 'fonts', 'profile-tools')
$fullSteps = @('full-apps', 'platform-automation')
$validSteps = $coreSteps + $fullSteps + @('wsl-host')
$selectedSteps = @($Step | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($selectedSteps.Count -eq 0) {
    $selectedSteps = if ($Preset -eq 'Full') { $coreSteps + $fullSteps } else { $coreSteps }
    if ($IncludeWsl) { $selectedSteps += 'wsl-host' }
}
$unknownSteps = @($selectedSteps | Where-Object { $_ -notin $validSteps })
if ($unknownSteps.Count -gt 0) {
    [Console]::Error.WriteLine("未知 Windows 验证步骤: $($unknownSteps -join ', ')")
    exit 2
}
if ($Preset -eq 'Core' -and @($selectedSteps | Where-Object { $_ -in $fullSteps }).Count -gt 0) {
    [Console]::Error.WriteLine('full-apps/platform-automation 不属于 Core 预设')
    exit 2
}
$effectiveIncludeWsl = $IncludeWsl -or 'wsl-host' -in $selectedSteps
try {
    $results = @(& $helperPath `
            -Step $selectedSteps `
            -Preset $Preset `
            -IncludeWsl:$effectiveIncludeWsl `
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
