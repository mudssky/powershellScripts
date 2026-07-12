<#
.SYNOPSIS
    比较 psutils 聚合 manifest、Profile 核心子模块和单独子模块的冷导入耗时。

.DESCRIPTION
    每个样本启动新的 pwsh -NoProfile 子进程，并由子进程内部的 Stopwatch 只测量
    Import-Module 调用。三种场景按轮次旋转执行顺序，降低固定顺序和缓存偏置。

.PARAMETER Iterations
    每个场景的正式采样轮数，默认 5。

.PARAMETER DirectModule
    单独子模块场景使用的模块名，默认 config。

.PARAMETER OutputPath
    可选 JSON 报告输出路径。

.PARAMETER AsJson
    只向 stdout 输出 JSON，不打印交互摘要。

.OUTPUTS
    System.String
    使用 -AsJson 时输出 JSON 字符串；默认只打印性能摘要。

.EXAMPLE
    pnpm benchmark -- psutils-import -Iterations 5

.EXAMPLE
    pnpm benchmark -- psutils-import -DirectModule commandDiscovery -AsJson
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 50)]
    [int]$Iterations = 5,
    [ValidateNotNullOrEmpty()]
    [string]$DirectModule = 'config',
    [string]$OutputPath,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PsutilsImportStats {
    <#
    .SYNOPSIS
        计算导入耗时样本的统计摘要。

    .PARAMETER Samples
        毫秒样本数组。

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        返回平均值、中位数、最小值、最大值和排序后的样本。
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

function Invoke-PsutilsImportSample {
    <#
    .SYNOPSIS
        在独立 PowerShell 进程内采集一次模块导入样本。

    .PARAMETER PwshPath
        pwsh 可执行文件路径。

    .PARAMETER ModulePaths
        本次样本需要依次导入的模块路径。

    .OUTPUTS
        System.Double
        返回子进程内部测得的模块导入毫秒数。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PwshPath,
        [Parameter(Mandatory)]
        [string[]]$ModulePaths
    )

    $pathLiterals = @($ModulePaths | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ', '
    $commandText = @"
`$ErrorActionPreference = 'Stop'
`$modulePaths = @($pathLiterals)
`$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
foreach (`$modulePath in `$modulePaths) {
    Import-Module `$modulePath -Force -ErrorAction Stop
}
`$stopwatch.Stop()
[Console]::Out.Write(`$stopwatch.Elapsed.TotalMilliseconds.ToString([Globalization.CultureInfo]::InvariantCulture))
"@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($commandText))
    $output = & $PwshPath -NoProfile -NoLogo -EncodedCommand $encodedCommand 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "psutils 导入样本失败: $($output -join [Environment]::NewLine)"
    }

    $elapsedMs = 0.0
    if (-not [double]::TryParse(
            ($output -join '').Trim(),
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$elapsedMs
        )) {
        throw "无法解析 psutils 导入耗时: $($output -join [Environment]::NewLine)"
    }

    return $elapsedMs
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$psutilsRoot = Join-Path $repoRoot 'psutils'
$manifestPath = Join-Path $psutilsRoot 'psutils.psd1'
$modulesRoot = Join-Path $psutilsRoot 'modules'
$directModulePath = Join-Path $modulesRoot "$DirectModule.psm1"
if (-not (Test-Path -LiteralPath $directModulePath)) {
    throw "psutils 子模块不存在: $directModulePath"
}

$coreModuleNames = if ($IsWindows) {
    @('os', 'cache', 'commandDiscovery', 'proxy', 'wrapper')
}
else {
    @('os', 'cache', 'commandDiscovery', 'env', 'proxy', 'wrapper')
}
$profileCorePaths = @($coreModuleNames | ForEach-Object { Join-Path $modulesRoot "$_.psm1" })
$scenarioPaths = [ordered]@{
    Aggregate   = @($manifestPath)
    ProfileCore = $profileCorePaths
    Direct      = @($directModulePath)
}
$scenarioSamples = [ordered]@{
    Aggregate   = [System.Collections.Generic.List[double]]::new()
    ProfileCore = [System.Collections.Generic.List[double]]::new()
    Direct      = [System.Collections.Generic.List[double]]::new()
}
$pwshPath = (Get-Process -Id $PID).Path
$scenarioNames = @($scenarioPaths.Keys)

for ($iteration = 0; $iteration -lt $Iterations; $iteration++) {
    $offset = $iteration % $scenarioNames.Count
    $executionOrder = @($scenarioNames[$offset..($scenarioNames.Count - 1)] + $scenarioNames[0..($offset - 1)])
    if ($offset -eq 0) {
        $executionOrder = $scenarioNames
    }

    foreach ($scenario in $executionOrder) {
        $elapsedMs = Invoke-PsutilsImportSample -PwshPath $pwshPath -ModulePaths $scenarioPaths[$scenario]
        $scenarioSamples[$scenario].Add($elapsedMs)
    }
}

$report = [PSCustomObject]@{
    GeneratedAt       = (Get-Date).ToString('o')
    Platform          = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Iterations        = $Iterations
    DirectModule      = $DirectModule
    CoreModules       = $coreModuleNames
    Aggregate         = Get-PsutilsImportStats -Samples $scenarioSamples.Aggregate.ToArray()
    ProfileCore       = Get-PsutilsImportStats -Samples $scenarioSamples.ProfileCore.ToArray()
    Direct            = Get-PsutilsImportStats -Samples $scenarioSamples.Direct.ToArray()
    Notes             = @(
        '每个样本使用新的 pwsh -NoProfile 子进程',
        '统计值只包含子进程内部 Import-Module 调用，不包含进程创建时间',
        '结果仅代表当前平台、当前磁盘缓存和当前机器'
    )
}

$json = $report | ConvertTo-Json -Depth 8
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

Write-Host '=== psutils 冷导入 benchmark ===' -ForegroundColor Cyan
Write-Host ("Platform: {0} | PowerShell: {1} | Samples: {2}" -f $report.Platform, $report.PowerShellVersion, $Iterations) -ForegroundColor DarkGray
Write-Host ("Aggregate   avg={0}ms median={1}ms min={2}ms max={3}ms" -f $report.Aggregate.AverageMs, $report.Aggregate.MedianMs, $report.Aggregate.MinMs, $report.Aggregate.MaxMs) -ForegroundColor Green
Write-Host ("ProfileCore avg={0}ms median={1}ms min={2}ms max={3}ms" -f $report.ProfileCore.AverageMs, $report.ProfileCore.MedianMs, $report.ProfileCore.MinMs, $report.ProfileCore.MaxMs) -ForegroundColor Green
Write-Host ("Direct({0}) avg={1}ms median={2}ms min={3}ms max={4}ms" -f $DirectModule, $report.Direct.AverageMs, $report.Direct.MedianMs, $report.Direct.MinMs, $report.Direct.MaxMs) -ForegroundColor Green
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Host ("JSON report: {0}" -f $OutputPath) -ForegroundColor DarkGray
}
