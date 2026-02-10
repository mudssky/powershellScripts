#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Pester测试框架配置脚本

.DESCRIPTION
    该脚本定义了Pester测试框架的配置参数，包括测试路径、并行执行设置、
    代码覆盖率分析等。配置用于自动化测试psutils模块的功能。

.EXAMPLE
    .\PesterConfiguration.ps1
    加载Pester测试配置

.NOTES
    配置包括：
    - 测试路径设置为./psutils目录
    - 启用并行测试，最大4个线程
    - 启用代码覆盖率分析
    - 排除特定模块的覆盖率统计
    - 输出格式为CoverageGutters
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$excludeTags = @('Slow')
if ($IsLinux -or $IsMacOS) {
    $excludeTags += 'windowsOnly'
}


$isCI = [bool]$env:CI
$testMode = if ([string]::IsNullOrWhiteSpace($env:PWSH_TEST_MODE)) { 'full' } else { $env:PWSH_TEST_MODE }
$isFast = $testMode -eq 'fast'

$config = @{
    Run          = @{
        Path     = @("./psutils", "./tests")
        # 输出测试结果对象，因为我不需要解析结果对象，所以关掉
        # PassThru = $True
        PassThru = $False
        # 多线程执行测试
        Parallel = @{
            Enabled    = $true
            MaxThreads = 4
        }

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
        Enabled                 = -not $isFast
        Path                    = "./psutils/modules/*.psm1"
        # OutputPath   = "./coverge.xml"
        OutputFormat            = 'CoverageGutters'
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
        Verbosity = if ($isCI) { 'Detailed' } else { 'Normal' }
    }
    TestResult   = @{
        Enabled       = $true
        OutputPath    = "testResults.xml"
        OutputFormat  = 'NUnit3'
        TestSuiteName = "PsUtils.Tests"  ## 可选：给你的测试套件起个名字
    }

}

$newConfig = New-PesterConfiguration -Hashtable $config
Write-Output $newConfig
