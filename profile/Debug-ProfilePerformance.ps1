#!/usr/bin/env pwsh
<#
.SYNOPSIS
    使用真实 Profile 入口执行多样本启动性能诊断。

.DESCRIPTION
    每个样本启动新的 pwsh -NoProfile 子进程并执行 profile.ps1，避免手工复制加载逻辑造成行为漂移。
    报告分别统计 Profile 内部阶段耗时与父进程观察到的完整子进程耗时。

.PARAMETER Mode
    要测量的 Profile 模式。

.PARAMETER Iterations
    新进程正式采样轮数。

.PARAMETER Phase
    人类可读输出中仅显示指定阶段序号；0 表示显示全部阶段。

.PARAMETER SkipStarship
    向真实 Profile 入口传递跳过 Starship 初始化开关。

.PARAMETER SkipZoxide
    向真实 Profile 入口传递跳过 Zoxide 初始化开关。

.PARAMETER SkipProxy
    向真实 Profile 入口传递跳过代理检测开关。

.PARAMETER SkipAliases
    向真实 Profile 入口传递跳过别名注册开关。

.PARAMETER OutputPath
    可选 JSON 报告输出路径。

.PARAMETER AsJson
    仅向 stdout 输出 JSON，不打印交互摘要。

.OUTPUTS
    System.String
    使用 -AsJson 时输出 JSON 字符串；默认仅打印摘要。

.EXAMPLE
    pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode Full -Iterations 5

.EXAMPLE
    pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode Minimal -Iterations 7 -AsJson
#>
[CmdletBinding()]
param(
    [ValidateSet('Full', 'Minimal', 'UltraMinimal')]
    [string]$Mode = 'Full',
    [ValidateRange(1, 100)]
    [int]$Iterations = 5,
    [ValidateRange(0, 10)]
    [int]$Phase = 0,
    [switch]$SkipStarship,
    [switch]$SkipZoxide,
    [switch]$SkipProxy,
    [switch]$SkipAliases,
    [string]$OutputPath,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProfileBenchmarkStats {
    <#
    .SYNOPSIS
        计算一组毫秒样本的稳定摘要。

    .PARAMETER Samples
        毫秒样本集合。

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        返回平均值、中位数、最小值、最大值与排序后的样本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double[]]$Samples
    )

    $ordered = @($Samples | Sort-Object)
    if ($ordered.Count -eq 0) {
        throw '性能样本不能为空'
    }

    $median = if ($ordered.Count % 2 -eq 1) {
        $ordered[[int]($ordered.Count / 2)]
    }
    else {
        ($ordered[($ordered.Count / 2) - 1] + $ordered[$ordered.Count / 2]) / 2
    }

    return [PSCustomObject]@{
        AverageMs = [math]::Round((($ordered | Measure-Object -Average).Average), 3)
        MedianMs  = [math]::Round($median, 3)
        MinMs     = [math]::Round($ordered[0], 3)
        MaxMs     = [math]::Round($ordered[-1], 3)
        SamplesMs = @($ordered | ForEach-Object { [math]::Round($_, 3) })
    }
}

function Invoke-ProfilePerformanceSample {
    <#
    .SYNOPSIS
        在独立 pwsh 进程中采集一次真实 Profile 性能样本。

    .PARAMETER PwshPath
        pwsh 可执行文件路径。

    .PARAMETER ProfilePath
        profile.ps1 绝对路径。

    .PARAMETER Mode
        要测量的 Profile 模式。

    .PARAMETER Iteration
        当前样本序号。

    .PARAMETER ProfileArguments
        需要透传给真实 Profile 入口的开关名称。

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        返回真实入口报告和完整子进程耗时。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PwshPath,
        [Parameter(Mandatory)]
        [string]$ProfilePath,
        [Parameter(Mandatory)]
        [ValidateSet('Full', 'Minimal', 'UltraMinimal')]
        [string]$Mode,
        [Parameter(Mandatory)]
        [int]$Iteration,
        [string[]]$ProfileArguments
    )

    $timingPath = Join-Path ([System.IO.Path]::GetTempPath()) ("profile-timing-{0}.json" -f [guid]::NewGuid().ToString('N'))
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $PwshPath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.ArgumentList.Add('-NoProfile')
        $startInfo.ArgumentList.Add('-NoLogo')
        $startInfo.ArgumentList.Add('-File')
        $startInfo.ArgumentList.Add($ProfilePath)
        $startInfo.ArgumentList.Add('-TimingOutputPath')
        $startInfo.ArgumentList.Add($timingPath)
        foreach ($argument in @($ProfileArguments)) {
            $startInfo.ArgumentList.Add($argument)
        }

        foreach ($environmentName in @(
                'POWERSHELL_PROFILE_FULL',
                'POWERSHELL_PROFILE_MODE',
                'POWERSHELL_PROFILE_ULTRA_MINIMAL',
                'POWERSHELL_PROFILE_TIMING',
                'CODEX_THREAD_ID',
                'CODEX_SANDBOX_NETWORK_DISABLED'
            )) {
            $startInfo.Environment.Remove($environmentName) | Out-Null
        }
        switch ($Mode) {
            'Full' { $startInfo.Environment['POWERSHELL_PROFILE_FULL'] = '1' }
            'Minimal' { $startInfo.Environment['POWERSHELL_PROFILE_MODE'] = 'minimal' }
            'UltraMinimal' { $startInfo.Environment['POWERSHELL_PROFILE_MODE'] = 'ultra' }
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $process.Start() | Out-Null
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stopwatch.Stop()
        $standardOutput = $stdoutTask.GetAwaiter().GetResult()
        $standardError = $stderrTask.GetAwaiter().GetResult()

        if ($process.ExitCode -ne 0) {
            throw "Profile 样本进程失败，exit=$($process.ExitCode): $standardError$standardOutput"
        }
        if (-not (Test-Path -LiteralPath $timingPath)) {
            throw "Profile 样本未生成计时报告: $standardError$standardOutput"
        }

        $profileReport = Get-Content -LiteralPath $timingPath -Raw | ConvertFrom-Json
        if ([string]$profileReport.FinalMode -ne $Mode) {
            throw "Profile 样本模式不一致: requested=$Mode final=$($profileReport.FinalMode)"
        }

        return [PSCustomObject]@{
            Iteration       = $Iteration
            ProcessElapsedMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
            ProfileReport   = $profileReport
        }
    }
    finally {
        Remove-Item -LiteralPath $timingPath -Force -ErrorAction SilentlyContinue
    }
}

$profileRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$profilePath = (Resolve-Path (Join-Path $profileRoot 'profile.ps1')).Path
$pwshPath = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
$profileArguments = [System.Collections.Generic.List[string]]::new()
if ($SkipStarship) { $profileArguments.Add('-SkipStarship') }
if ($SkipZoxide) { $profileArguments.Add('-SkipZoxide') }
if ($SkipProxy) { $profileArguments.Add('-SkipProxy') }
if ($SkipAliases) { $profileArguments.Add('-SkipAliases') }

$samples = [System.Collections.Generic.List[object]]::new()
for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    $sample = Invoke-ProfilePerformanceSample `
        -PwshPath $pwshPath `
        -ProfilePath $profilePath `
        -Mode $Mode `
        -Iteration $iteration `
        -ProfileArguments $profileArguments.ToArray()
    $samples.Add($sample)
}

$firstReport = $samples[0].ProfileReport
$phaseStats = [ordered]@{}
$phaseNames = @($firstReport.Timings.PSObject.Properties.Name | Where-Object { $_ -ne 'total' })
foreach ($phaseName in $phaseNames) {
    $phaseSamples = @($samples | ForEach-Object { [double]$_.ProfileReport.Timings.$phaseName })
    $phaseStats[$phaseName] = Get-ProfileBenchmarkStats -Samples $phaseSamples
}

$report = [PSCustomObject]@{
    GeneratedAt       = (Get-Date).ToString('o')
    Platform          = [string]$firstReport.Platform
    PowerShellVersion = [string]$firstReport.PowerShellVersion
    Mode              = $Mode
    Iterations        = $Iterations
    ProfileInternal   = Get-ProfileBenchmarkStats -Samples @($samples | ForEach-Object { [double]$_.ProfileReport.ProfileInternalMs })
    ProcessElapsed    = Get-ProfileBenchmarkStats -Samples @($samples | ForEach-Object { [double]$_.ProcessElapsedMs })
    Phases            = [PSCustomObject]$phaseStats
    Samples           = @($samples | ForEach-Object {
            [PSCustomObject]@{
                Iteration        = $_.Iteration
                ProfileInternalMs = [double]$_.ProfileReport.ProfileInternalMs
                ProcessElapsedMs = [double]$_.ProcessElapsedMs
            }
        })
    Notes             = @(
        '每个样本使用新的 pwsh -NoProfile 子进程执行真实 profile.ps1',
        'ProfileInternal 不包含 pwsh 进程创建成本，ProcessElapsed 包含完整子进程生命周期',
        '结果仅代表当前平台、当前缓存状态与当前机器，不应外推为跨平台绝对基线'
    )
}

$json = $report | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $json | Set-Content -LiteralPath $resolvedOutputPath -Encoding utf8NoBOM
}

if ($AsJson) {
    $json
    return
}

Write-Host '=== Profile 真实入口性能诊断 ===' -ForegroundColor Cyan
Write-Host ("Platform: {0} | PowerShell: {1} | Mode: {2} | Samples: {3}" -f $report.Platform, $report.PowerShellVersion, $Mode, $Iterations) -ForegroundColor DarkGray
Write-Host ("Profile internal  avg={0}ms median={1}ms min={2}ms max={3}ms" -f $report.ProfileInternal.AverageMs, $report.ProfileInternal.MedianMs, $report.ProfileInternal.MinMs, $report.ProfileInternal.MaxMs) -ForegroundColor Green
Write-Host ("Process elapsed   avg={0}ms median={1}ms min={2}ms max={3}ms" -f $report.ProcessElapsed.AverageMs, $report.ProcessElapsed.MedianMs, $report.ProcessElapsed.MinMs, $report.ProcessElapsed.MaxMs) -ForegroundColor Green
Write-Host ''
Write-Host '=== 阶段中位数 ===' -ForegroundColor Cyan

$displayPhases = @($report.Phases.PSObject.Properties)
if ($Phase -gt 0) {
    if ($Phase -gt $displayPhases.Count) {
        throw "Phase 超出范围，当前报告只有 $($displayPhases.Count) 个阶段"
    }
    $displayPhases = @($displayPhases[$Phase - 1])
}
foreach ($phaseProperty in $displayPhases) {
    Write-Host ("  {0,-36} {1,8}ms" -f $phaseProperty.Name, $phaseProperty.Value.MedianMs)
}
