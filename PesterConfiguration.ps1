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
    $excludeTags += 'windows'
}

$config = @{
    Run          = @{
        Path     = "./psutils"
        # 输出测试结果对象，因为我不需要解析结果对象，所以关掉
        # PassThru = $True
        PassThru = $False
        # 多线程执行测试
        Parallel = @{
            Enabled    = $true
            MaxThreads = 4
        }
    }

    # Filter 模块: 定义筛选规则
    Filter       = @{
        ExcludeTag = $excludeTags
    }
    CodeCoverage = @{
        Enabled                 = $true
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
