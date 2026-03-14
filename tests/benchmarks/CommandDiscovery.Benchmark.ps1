<#
.SYNOPSIS
    对比 Find-ExecutableCommand 与 Get-Command 的冷启动性能。

.DESCRIPTION
    使用全新的 `pwsh -NoProfile` 子进程多次测量两种命令探测方式的耗时，
    重点复现 Profile 冷启动场景下的真实差距。默认命令集合与当前平台的
    Profile 探测范围保持一致：

    - Windows: starship, zoxide, sccache, scoop, winget, choco
    - macOS: starship, zoxide, sccache, fnm, brew
    - Linux: starship, zoxide, sccache, fnm, brew, apt

.PARAMETER CommandNames
    自定义要探测的命令名集合。

.PARAMETER Iterations
    每种探测方式执行的轮数。默认 5。

.PARAMETER OutputPath
    可选的 JSON 输出文件路径。

.PARAMETER AsJson
    仅输出 JSON 结果，便于脚本消费。

.EXAMPLE
    pnpm benchmark -- command-discovery

.EXAMPLE
    pnpm benchmark -- command-discovery -Iterations 8 -CommandNames choco,brew,apt
#>

[CmdletBinding()]
param(
    [string[]]$CommandNames,
    [ValidateRange(1, 100)]
    [int]$Iterations = 5,
    [string]$OutputPath,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DefaultBenchmarkCommandNames {
    [CmdletBinding()]
    param()

    if ($IsWindows) {
        return @('starship', 'zoxide', 'sccache', 'scoop', 'winget', 'choco')
    }

    if ($IsMacOS) {
        return @('starship', 'zoxide', 'sccache', 'fnm', 'brew')
    }

    return @('starship', 'zoxide', 'sccache', 'fnm', 'brew', 'apt')
}

function ConvertTo-EncodedPwshCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Script
    )

    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Script))
}

function New-BenchmarkChildScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('find', 'get-command')]
        [string]$Mode,
        [Parameter(Mandatory)]
        [string[]]$Names,
        [Parameter(Mandatory)]
        [string]$ModulePath
    )

    $namesJson = ($Names | ConvertTo-Json -Compress)
    $namesBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($namesJson))
    $escapedModulePath = $ModulePath.Replace("'", "''")

    if ($Mode -eq 'find') {
        return @"
`$ErrorActionPreference = 'Stop'
Import-Module '$escapedModulePath' -Force
`$commandNames = @((([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$namesBase64'))) | ConvertFrom-Json))
`$sw = [System.Diagnostics.Stopwatch]::StartNew()
Find-ExecutableCommand -Name `$commandNames -CacheMisses | Out-Null
`$sw.Stop()
[Console]::Out.WriteLine(`$sw.Elapsed.TotalMilliseconds.ToString('F3', [System.Globalization.CultureInfo]::InvariantCulture))
"@
    }

    return @"
`$ErrorActionPreference = 'Stop'
`$commandNames = @((([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$namesBase64'))) | ConvertFrom-Json))
`$sw = [System.Diagnostics.Stopwatch]::StartNew()
Get-Command -Name `$commandNames -CommandType Application -ErrorAction SilentlyContinue | Out-Null
`$sw.Stop()
[Console]::Out.WriteLine(`$sw.Elapsed.TotalMilliseconds.ToString('F3', [System.Globalization.CultureInfo]::InvariantCulture))
"@
}

function Invoke-BenchmarkSample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('find', 'get-command')]
        [string]$Mode,
        [Parameter(Mandatory)]
        [string[]]$Names,
        [Parameter(Mandatory)]
        [string]$ModulePath,
        [Parameter(Mandatory)]
        [string]$PwshPath
    )

    $childScript = New-BenchmarkChildScript -Mode $Mode -Names $Names -ModulePath $ModulePath
    $encodedCommand = ConvertTo-EncodedPwshCommand -Script $childScript
    $rawResult = & $PwshPath -NoProfile -NoLogo -EncodedCommand $encodedCommand
    if ($LASTEXITCODE -ne 0) {
        throw "基准子进程执行失败: $Mode"
    }

    return [double]::Parse($rawResult.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-BenchmarkStats {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double[]]$Samples
    )

    $ordered = @($Samples | Sort-Object)
    $median = if ($ordered.Count % 2 -eq 1) {
        $ordered[[int]($ordered.Count / 2)]
    }
    else {
        ($ordered[($ordered.Count / 2) - 1] + $ordered[$ordered.Count / 2]) / 2
    }

    return [PSCustomObject]@{
        Iterations = $ordered.Count
        AverageMs  = [math]::Round((($ordered | Measure-Object -Average).Average), 3)
        MinMs      = [math]::Round($ordered[0], 3)
        MaxMs      = [math]::Round($ordered[-1], 3)
        MedianMs   = [math]::Round($median, 3)
        SamplesMs  = @($ordered | ForEach-Object { [math]::Round($_, 3) })
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$modulePath = Join-Path $repoRoot 'psutils' 'modules' 'commandDiscovery.psm1'
if (-not (Test-Path $modulePath)) {
    throw "模块不存在: $modulePath"
}

$pwshPath = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($pwshPath)) {
    $pwshPath = 'pwsh'
}

$effectiveCommandNames = if ($CommandNames -and $CommandNames.Count -gt 0) {
    $CommandNames
}
else {
    Get-DefaultBenchmarkCommandNames
}

$findSamples = [System.Collections.Generic.List[double]]::new()
$getCommandSamples = [System.Collections.Generic.List[double]]::new()

for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    $order = if ($iteration % 2 -eq 1) {
        @('get-command', 'find')
    }
    else {
        @('find', 'get-command')
    }

    foreach ($mode in $order) {
        $sample = Invoke-BenchmarkSample -Mode $mode -Names $effectiveCommandNames -ModulePath $modulePath -PwshPath $pwshPath
        if ($mode -eq 'find') {
            $findSamples.Add($sample) | Out-Null
        }
        else {
            $getCommandSamples.Add($sample) | Out-Null
        }
    }
}

$findStats = Get-BenchmarkStats -Samples $findSamples.ToArray()
$getCommandStats = Get-BenchmarkStats -Samples $getCommandSamples.ToArray()
$speedup = if ($findStats.AverageMs -gt 0) {
    [math]::Round(($getCommandStats.AverageMs / $findStats.AverageMs), 3)
}
else {
    $null
}

$report = [PSCustomObject]@{
    GeneratedAt   = (Get-Date).ToString('o')
    Platform      = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
    PwshPath      = $pwshPath
    Iterations    = $Iterations
    CommandNames  = @($effectiveCommandNames)
    FindCommand   = $findStats
    GetCommand    = $getCommandStats
    SpeedupVsGet  = $speedup
    Notes         = @(
        '每个样本都在全新的 pwsh -NoProfile 子进程中执行'
        'Find-ExecutableCommand 的模块导入成本不计入计时'
        '结果主要用于对比冷启动命令探测阶段的纯耗时差异'
    )
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    $report | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding utf8NoBOM
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 6
    return
}

Write-Host '=== Command Discovery Benchmark ===' -ForegroundColor Cyan
Write-Host ("Platform: {0}" -f $report.Platform) -ForegroundColor DarkGray
Write-Host ("Iterations: {0}" -f $Iterations) -ForegroundColor DarkGray
Write-Host ("Commands: {0}" -f ($effectiveCommandNames -join ', ')) -ForegroundColor DarkGray
Write-Host ''

Write-Host 'Find-ExecutableCommand' -ForegroundColor Green
Write-Host ("  avg:    {0} ms" -f $findStats.AverageMs)
Write-Host ("  median: {0} ms" -f $findStats.MedianMs)
Write-Host ("  min/max:{0} / {1} ms" -f $findStats.MinMs, $findStats.MaxMs)
Write-Host ("  samples:{0}" -f (($findStats.SamplesMs | ForEach-Object { $_.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture) }) -join ', '))
Write-Host ''

Write-Host 'Get-Command -CommandType Application' -ForegroundColor Yellow
Write-Host ("  avg:    {0} ms" -f $getCommandStats.AverageMs)
Write-Host ("  median: {0} ms" -f $getCommandStats.MedianMs)
Write-Host ("  min/max:{0} / {1} ms" -f $getCommandStats.MinMs, $getCommandStats.MaxMs)
Write-Host ("  samples:{0}" -f (($getCommandStats.SamplesMs | ForEach-Object { $_.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture) }) -join ', '))
Write-Host ''

if ($null -ne $speedup) {
    Write-Host ("Speedup (Get-Command / Find-ExecutableCommand): {0}x" -f $speedup) -ForegroundColor Cyan
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Host ("JSON report: {0}" -f $OutputPath) -ForegroundColor DarkGray
}
