#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Pester测试框架配置脚本

.DESCRIPTION
    该脚本定义了Pester测试框架的配置参数，包括测试路径、运行模式、
    代码覆盖率分析等。配置用于自动化测试psutils模块的功能。

.EXAMPLE
    .\PesterConfiguration.ps1
    加载Pester测试配置

.NOTES
    配置包括：
    - 测试路径设置为./psutils目录
    - 默认按仓库固定 Pester 版本串行执行，显式开关可运行 Pester 6 并行 PoC
    - 启用代码覆盖率分析
    - 排除特定模块的覆盖率统计
    - coverage 输出格式为 JaCoCo，兼容 Pester 5.7.1 与 6.1.0
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PowerShell 7.5 会在交互终端为 Pester TestDrive 清理渲染
# `Removed x of y files` 进度行。只静音 Remove-Item 的进度流，
# 保留其他命令的进度、warning、error 和测试输出。
$global:PSDefaultParameterValues['Remove-Item:ProgressAction'] = 'SilentlyContinue'

$reportDirectory = Join-Path $PSScriptRoot 'tests/reports'
if (-not (Test-Path -LiteralPath $reportDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
}
$defaultCoveragePath = Join-Path $reportDirectory 'coverage.xml'
$defaultTestResultPath = Join-Path $reportDirectory 'testResults.xml'
$coveragePath = if (-not [string]::IsNullOrWhiteSpace($env:PESTER_COVERAGE_PATH)) { $env:PESTER_COVERAGE_PATH } else { $defaultCoveragePath }

$includeSlow = $env:PWSH_TEST_INCLUDE_SLOW -in @('1', 'true', 'yes', 'on')
$excludeTags = @(
    if (-not $includeSlow) { 'Slow' }
    if ($IsLinux -or $IsMacOS) { 'windowsOnly' }
)


$isCI = $env:CI -in @('true', '1', 'yes', 'on')
$testMode = if ([string]::IsNullOrWhiteSpace($env:PWSH_TEST_MODE)) { 'full' } else { $env:PWSH_TEST_MODE.Trim().ToLowerInvariant() }
$isQa = $testMode -eq 'qa'
$isFast = $testMode -in @('fast', 'serial', 'debug', 'qa')
$isSerial = $testMode -eq 'serial'
$isDebug = $testMode -eq 'debug'
$isVerbose = -not [string]::IsNullOrWhiteSpace($env:PWSH_TEST_VERBOSE)
$isParallel = $env:PWSH_TEST_PARALLEL -in @('1', 'true', 'yes', 'on')
$parallelThrottle = if ([string]::IsNullOrWhiteSpace($env:PWSH_TEST_PARALLEL_THROTTLE)) {
    0
}
else {
    $parsedThrottle = 0
    if (-not [int]::TryParse($env:PWSH_TEST_PARALLEL_THROTTLE, [ref]$parsedThrottle) -or $parsedThrottle -lt 0 -or $parsedThrottle -gt 128) {
        throw "PWSH_TEST_PARALLEL_THROTTLE 必须为 0 到 128 的整数: $env:PWSH_TEST_PARALLEL_THROTTLE"
    }
    $parsedThrottle
}
$coverageOverride = if ([string]::IsNullOrWhiteSpace($env:PWSH_TEST_ENABLE_COVERAGE)) {
    $null
}
else {
    $env:PWSH_TEST_ENABLE_COVERAGE.Trim().ToLowerInvariant()
}
$isCoverageEnabled = if ($coverageOverride -in @('1', 'true', 'yes', 'on')) {
    $true
}
elseif ($coverageOverride -in @('0', 'false', 'no', 'off')) {
    $false
}
else {
    -not $isFast
}

$qaDefaultPaths = @(
    "./tests/DeferredLoading.Tests.ps1"
    "./tests/losslessToAdaptiveAudio.Tests.ps1"
    "./tests/ProfileInstallHints.Tests.ps1"
    "./tests/ProfileLoading.Tests.ps1"
    "./tests/ProfileMode.Tests.ps1"
    "./tests/Install.Tests.ps1"
    "./tests/InstallOrchestrator.Tests.ps1"
    "./tests/LinuxInstallPipeline.Tests.ps1"
    "./tests/MacOSInstallPipeline.Tests.ps1"
    "./tests/PackageSourceBootstrap.Tests.ps1"
    "./tests/PackageSources.Tests.ps1"
    "./psutils/tests/commandDiscovery.Tests.ps1"
    "./tests/Switch-Mirrors.Tests.ps1"
    "./tests/WindowsInstallPipeline.Tests.ps1"
    "./tests/WindowsInstallEntrypoint.Tests.ps1"
    "./psutils/tests/error.Tests.ps1"
    "./psutils/tests/filesystem.Tests.ps1"
    "./psutils/tests/font.Tests.ps1"
    "./psutils/tests/git.Tests.ps1"
    "./psutils/tests/string.Tests.ps1"
    "./psutils/tests/win.Tests.ps1"
    "./psutils/tests/wrapper.Tests.ps1"
)

$runPaths = if ($isQa) { $qaDefaultPaths } else { @("./psutils", "./tests") }
if (-not [string]::IsNullOrWhiteSpace($env:PWSH_TEST_PATH)) {
    $runPaths = $env:PWSH_TEST_PATH -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

if ($isQa) {
    $excludeTags += 'QaSkip'
}

$config = @{
    Run          = @{
        Path     = $runPaths
        # 输出测试结果对象，因为我不需要解析结果对象，所以关掉
        # PassThru = $True
        PassThru = $False
        # 关键点：
        # 本地运行 (False): 测试失败仅仅显示红色，不退出 PowerShell 进程
        # CI 运行 (True): 测试失败会返回非零 ExitCode，让 GitHub Action 标记为失败
        Exit     = $isCI 
    }

    # Filter 模块: 定义筛选规则
    Filter       = @{
        ExcludeTag = $excludeTags
    }
    CodeCoverage = @{
        # coverage 开关与输出路径分别由统一 runner 和 artifact reporter 注入；
        # 默认仍写入仓库 reports 目录，连续或并行采样可使用唯一覆盖路径。
        Enabled                 = $isCoverageEnabled
        Path                    = "./psutils/modules/*.psm1"
        # 显式写回仓库当前采用的 50% 覆盖率门槛，避免继续沿用 Pester 默认 75%
        # 导致控制台输出与 OpenSpec 规范长期漂移。
        CoveragePercentTarget   = 50
        OutputPath              = $coveragePath
        OutputFormat            = 'JaCoCo'
        ExcludeFromCodeCoverage = @(
            './psutils/modules/error.psm1'
            './psutils/modules/linux.psm1'
            './psutils/modules/network.psm1'
            './psutils/modules/proxy.psm1'
            './psutils/modules/pwsh.psm1'
        )

    }
    Output       = @{
        # 使用详细输出，方便查看哪些测试被跳过了
        # Verbosity = 'Detailed'
        # CI 环境用详细输出方便排错，本地用 Normal 保持清爽
        Verbosity  = if ($isCI -or $isDebug -or $isVerbose) { 'Detailed' } else { 'Normal' }
        # 支持 NO_COLOR 标准 (https://no-color.org/)
        RenderMode = if (-not [string]::IsNullOrEmpty($env:NO_COLOR)) { 'Plaintext' } else { 'Auto' }
    }
    TestResult   = @{
        Enabled       = $true
        # 支持环境变量覆盖输出路径，用于并发 host/container 运行时避免冲突
        OutputPath    = if (-not [string]::IsNullOrWhiteSpace($env:PESTER_RESULT_PATH)) { $env:PESTER_RESULT_PATH } else { $defaultTestResultPath }
        OutputFormat  = 'NUnit3'
        TestSuiteName = "PsUtils.Tests"  ## 可选：给你的测试套件起个名字
    }
    TestRegistry = @{
        Enabled = $false
    }

}

if ($isParallel) {
    $configurationProbe = New-PesterConfiguration
    if ($configurationProbe.Run.PSObject.Properties.Name -notcontains 'Parallel') {
        throw "当前 Pester 版本不支持 Run.Parallel，不能执行并行性能样本。"
    }

    $loadedPester = Get-Module -Name Pester | Select-Object -First 1
    if ($isCoverageEnabled -and (-not $loadedPester -or $loadedPester.Version -lt [version]'6.1.0')) {
        $loadedVersion = if ($loadedPester) { $loadedPester.Version.ToString() } else { 'unknown' }
        throw "Pester $loadedVersion 不支持并行 coverage；需要 Pester 6.1.0 或更高版本。"
    }

    $config.Run.Parallel = $true
    $config.Run.ParallelThrottleLimit = $parallelThrottle
}

$newConfig = New-PesterConfiguration -Hashtable $config
Write-Output $newConfig
