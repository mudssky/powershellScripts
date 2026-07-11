<#
.SYNOPSIS
    测量 PackageSources Pester 测试文件的完整执行耗时。

.DESCRIPTION
    每次采样使用全新的 pwsh -NoProfile 子进程，以安静模式运行指定 Pester
    文件，并报告平均值、中位数与最慢值。CI 只应验证输出合同，不应使用
    单台机器的绝对耗时作为失败门槛。

.PARAMETER Iterations
    采样次数，默认 3 次。

.PARAMETER TestPath
    要执行的 Pester 测试文件，默认指向 tests/PackageSources.Tests.ps1。

.PARAMETER OutputPath
    可选的 JSON 报告输出路径。

.PARAMETER AsJson
    仅向 stdout 输出 JSON 报告。

.EXAMPLE
    pnpm benchmark -- package-sources-test -Iterations 3 -AsJson
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$Iterations = 3,
    [string]$TestPath,
    [string]$OutputPath,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-PackageSourceBenchmarkEncodedCommand {
    <#
    .SYNOPSIS
        将子进程脚本编码为 PowerShell EncodedCommand。

    .PARAMETER Script
        要编码的 PowerShell 脚本文本。

    .OUTPUTS
        string。UTF-16LE Base64 编码命令。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Script
    )

    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Script))
}

function Invoke-PackageSourceTestBenchmarkSample {
    <#
    .SYNOPSIS
        在全新 PowerShell 子进程中运行一次 Pester 测试。

    .PARAMETER Path
        要运行的 Pester 测试文件绝对路径。

    .PARAMETER PwshPath
        PowerShell 可执行文件路径。

    .OUTPUTS
        PSCustomObject。包含耗时与 Pester 通过、失败、跳过计数。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$PwshPath
    )

    $escapedPath = $Path.Replace("'", "''")
    $childScript = @"
`$ErrorActionPreference = 'Stop'
`$configuration = New-PesterConfiguration
`$configuration.Run.Path = '$escapedPath'
`$configuration.Run.PassThru = `$true
`$configuration.Output.Verbosity = 'None'
`$result = Invoke-Pester -Configuration `$configuration
[Console]::Out.WriteLine((@{
    Passed = `$result.PassedCount
    Failed = `$result.FailedCount
    Skipped = `$result.SkippedCount
} | ConvertTo-Json -Compress))
if (`$result.FailedCount -gt 0) { exit 1 }
"@

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PwshPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-NoLogo')
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-EncodedCommand')
    $startInfo.ArgumentList.Add((ConvertTo-PackageSourceBenchmarkEncodedCommand -Script $childScript))

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $stopwatch.Stop()

    if ($process.ExitCode -ne 0) {
        throw "Pester benchmark 子进程失败: $stderr$stdout"
    }

    $testResult = $stdout.Trim() | ConvertFrom-Json
    return [PSCustomObject]@{
        DurationMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
        Passed     = [int]$testResult.Passed
        Failed     = [int]$testResult.Failed
        Skipped    = [int]$testResult.Skipped
    }
}

function Get-PackageSourceTestBenchmarkStats {
    <#
    .SYNOPSIS
        计算 benchmark 样本的汇总统计。

    .PARAMETER Samples
        毫秒耗时样本。

    .OUTPUTS
        PSCustomObject。包含平均值、中位数、最快值、最慢值和有序样本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double[]]$Samples
    )

    $ordered = @($Samples | Sort-Object)
    $middle = [int]($ordered.Count / 2)
    $median = if ($ordered.Count % 2 -eq 1) {
        $ordered[$middle]
    }
    else {
        ($ordered[$middle - 1] + $ordered[$middle]) / 2
    }

    return [PSCustomObject]@{
        AverageMs = [math]::Round((($ordered | Measure-Object -Average).Average), 3)
        MedianMs  = [math]::Round($median, 3)
        MinMs     = [math]::Round($ordered[0], 3)
        MaxMs     = [math]::Round($ordered[-1], 3)
        SamplesMs = @($ordered | ForEach-Object { [math]::Round($_, 3) })
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$effectiveTestPath = if ([string]::IsNullOrWhiteSpace($TestPath)) {
    Join-Path $repoRoot 'tests' 'PackageSources.Tests.ps1'
}
else {
    (Resolve-Path -LiteralPath $TestPath -ErrorAction Stop).Path
}
if (-not (Test-Path -LiteralPath $effectiveTestPath -PathType Leaf)) {
    throw "Pester 测试文件不存在: $effectiveTestPath"
}

$pwshPath = (Get-Process -Id $PID).Path
$samples = [System.Collections.Generic.List[object]]::new()
for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    $samples.Add((Invoke-PackageSourceTestBenchmarkSample -Path $effectiveTestPath -PwshPath $pwshPath))
}

$stats = Get-PackageSourceTestBenchmarkStats -Samples @($samples | ForEach-Object { $_.DurationMs })
$report = [PSCustomObject]@{
    GeneratedAt = (Get-Date).ToString('o')
    Platform    = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
    PwshVersion = $PSVersionTable.PSVersion.ToString()
    TestPath    = $effectiveTestPath
    Iterations  = $Iterations
    Passed      = $samples[-1].Passed
    Failed      = $samples[-1].Failed
    Skipped     = $samples[-1].Skipped
    AverageMs   = $stats.AverageMs
    MedianMs    = $stats.MedianMs
    MinMs       = $stats.MinMs
    MaxMs       = $stats.MaxMs
    SamplesMs   = $stats.SamplesMs
}
$json = $report | ConvertTo-Json -Depth 4

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8NoBOM
}

if ($AsJson) {
    $json
    return
}

Write-Host '=== PackageSources Test Benchmark ===' -ForegroundColor Cyan
Write-Host ("Platform / PowerShell: {0} / {1}" -f $report.Platform, $report.PwshVersion)
Write-Host ("Iterations: {0}; passed: {1}; skipped: {2}" -f $Iterations, $report.Passed, $report.Skipped)
Write-Host ("Average / median / slowest: {0} / {1} / {2} ms" -f $report.AverageMs, $report.MedianMs, $report.MaxMs)
Write-Host ("Samples: {0}" -f ($report.SamplesMs -join ', '))
