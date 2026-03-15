# Best Practices

## 高性能 PowerShell benchmark 的目标

这份文档只回答一个问题：怎样把 PowerShell 性能测试写得既快又准，而且结果可复现。

适用场景：

- 新增 `tests/benchmarks/*.Benchmark.ps1`
- 现有 benchmark 数字波动很大
- 需要把一次性的 `Measure-Command` 排查收敛成长期可维护的 benchmark
- 需要给 Pester / CI 增加性能相关护栏，但不想把脆弱的单机数字写死

## 1. 先固定测量口径

写 benchmark 前先把下面三件事写清楚：

- 测冷启动、热路径，还是 profile 分阶段耗时
- 计时是否包含 `Import-Module`、缓存预热、外部命令探测
- 样本是在新进程里采，还是在当前会话里重复执行

### 示例：把冷启动和热路径拆开

```powershell
<#
.SYNOPSIS
    演示如何显式区分冷启动与热路径 benchmark。

.DESCRIPTION
    冷启动 benchmark 使用新的 `pwsh -NoProfile` 子进程，
    热路径 benchmark 在当前进程 warm-up 后重复采样。
#>

[CmdletBinding()]
param(
    [ValidateSet('ColdStart', 'HotPath')]
    [string]$Scenario = 'ColdStart'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

switch ($Scenario) {
    'ColdStart' {
        # 冷启动场景只统计子进程内目标逻辑，避免当前会话缓存污染。
        & pwsh -NoProfile -NoLogo -Command 'Get-Command pwsh | Out-Null'
    }
    'HotPath' {
        # 热路径场景先 warm-up，一次性成本不记入正式样本。
        Get-Command pwsh | Out-Null
        Get-Command pwsh | Out-Null
    }
}
```

## 2. 让 benchmark 自己尽量“安静”

高频采样时，benchmark 自己的额外开销必须尽量低：

- 计时用 `[System.Diagnostics.Stopwatch]`
- 样本集合用 `[System.Collections.Generic.List[double]]`
- JSON 转换、文件写入、彩色摘要都放到采样结束后
- `-AsJson` 模式下不要再输出 `Write-Host`

### 示例：推荐的采样骨架

```powershell
<#
.SYNOPSIS
    演示仓库推荐的 benchmark 采样骨架。

.PARAMETER Iterations
    正式采样轮数。

.PARAMETER OutputPath
    可选的 JSON 输出路径。

.PARAMETER AsJson
    仅输出 JSON，避免 stdout 被日志污染。
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$Iterations = 5,
    [string]$OutputPath,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
        AverageMs = [math]::Round((($ordered | Measure-Object -Average).Average), 3)
        MedianMs  = [math]::Round($median, 3)
        MinMs     = [math]::Round($ordered[0], 3)
        MaxMs     = [math]::Round($ordered[-1], 3)
        SamplesMs = @($ordered | ForEach-Object { [math]::Round($_, 3) })
    }
}

$samples = [System.Collections.Generic.List[double]]::new()

for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # 这里只保留被测逻辑，避免目录扫描、日志输出等噪声混入样本。
    Get-Command pwsh -CommandType Application | Out-Null

    $stopwatch.Stop()
    [void]$samples.Add($stopwatch.Elapsed.TotalMilliseconds)
}

$report = [PSCustomObject]@{
    GeneratedAt = (Get-Date).ToString('o')
    Iterations  = $Iterations
    Stats       = Get-BenchmarkStats -Samples $samples.ToArray()
    Notes       = @('采样循环不做 JSON 转换，也不打印交互日志')
}

if ($OutputPath) {
    $report | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding utf8NoBOM
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 5
    return
}

Write-Host ("avg: {0} ms" -f $report.Stats.AverageMs) -ForegroundColor Cyan
```

## 3. A/B 对照要交替执行，避免顺序偏置

对比两种实现时，不要先跑完 A 再跑完 B。正确做法是交替执行，降低缓存和宿主抖动带来的顺序偏置。

### 示例：交替执行两种实现

```powershell
<#
.SYNOPSIS
    演示 A/B 对照 benchmark 的交替执行顺序。
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$Iterations = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$samplesA = [System.Collections.Generic.List[double]]::new()
$samplesB = [System.Collections.Generic.List[double]]::new()

for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    # 奇偶轮切换顺序，避免同一个实现总是先跑。
    $order = if ($iteration % 2 -eq 1) { @('A', 'B') } else { @('B', 'A') }

    foreach ($mode in $order) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        if ($mode -eq 'A') {
            Get-Command pwsh -CommandType Application | Out-Null
        }
        else {
            [System.IO.File]::Exists((Get-Command pwsh).Source) | Out-Null
        }

        $stopwatch.Stop()

        if ($mode -eq 'A') {
            [void]$samplesA.Add($stopwatch.Elapsed.TotalMilliseconds)
        }
        else {
            [void]$samplesB.Add($stopwatch.Elapsed.TotalMilliseconds)
        }
    }
}
```

## 4. 机器可读输出要稳定

Benchmark 需要同时照顾两种消费方式：

- 人读：控制台摘要
- 脚本读：`-AsJson` / `-OutputPath`

规则很简单：

- `-AsJson` 只输出 JSON
- 交互摘要只在非 `-AsJson` 模式下输出
- 输出对象要带时间、平台、输入参数、统计值和限制说明

### 示例：`-AsJson` 与 `-OutputPath` 契约

```powershell
<#
.SYNOPSIS
    演示 benchmark 的结构化输出契约。
#>

[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$report = [PSCustomObject]@{
    GeneratedAt = (Get-Date).ToString('o')
    Platform    = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
    Scenario    = 'demo'
    Stats       = [PSCustomObject]@{
        AverageMs = 12.345
        MedianMs  = 11.876
    }
    Notes       = @('示例输出：真实 benchmark 应写入实际采样值')
}

$json = $report | ConvertTo-Json -Depth 5

if ($OutputPath) {
    $json | Set-Content -Path $OutputPath -Encoding utf8NoBOM
}

if ($AsJson) {
    $json
    return
}

Write-Host ("JSON report: {0}" -f $OutputPath) -ForegroundColor DarkGray
```

## 5. Pester 先保护契约，不要先保护脆弱数字

适合进 CI 的通常不是“必须小于 123ms”，而是这些内容：

- benchmark 能被 `pnpm benchmark -- --list` 发现
- 显式 benchmark 名称可以运行
- `-AsJson` 输出可被脚本解析
- `-OutputPath` 能正常落盘
- 关键参数能覆盖主要分支

### 示例：Pester 契约测试骨架

```powershell
Describe 'Demo.Benchmark.ps1' {
    It '输出的 JSON 可以被脚本解析' {
        $outputPath = Join-Path $TestDrive 'demo-benchmark.json'

        & pwsh -NoProfile -File ./tests/benchmarks/Demo.Benchmark.ps1 `
            -AsJson `
            -OutputPath $outputPath

        $LASTEXITCODE | Should -Be 0
        (Test-Path $outputPath) | Should -BeTrue

        $report = Get-Content -Path $outputPath -Raw | ConvertFrom-Json
        $report.GeneratedAt | Should -Not -BeNullOrEmpty
        $report.Stats.AverageMs | Should -BeGreaterOrEqual 0
    }
}
```

## 6. 常见反模式

- 用 `Measure-Command` 包住整段脚本，再把单次结果当长期基准
- 在采样循环里 `+=` 收集样本
- 在 `-AsJson` 模式下继续 `Write-Host`
- 先跑完全部 A 再跑全部 B
- 把模块导入、缓存预热、目录扫描和目标逻辑耗时混成一个数字
- 在 benchmark 里做网络请求或交互输入，导致结果主要反映环境抖动

## 7. 写完后的自检清单

- 这个 benchmark 解决的是冷启动、热路径还是 profile 分阶段问题
- 采样循环里是否只包含目标逻辑
- 是否使用 `Stopwatch` 和 `List[double]`
- 是否支持 `-AsJson` / `-OutputPath`
- 是否写清楚 `Notes` / `Limitations`
- 是否补了 Pester 契约测试，而不是脆弱的绝对耗时断言
