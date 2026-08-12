Describe 'PesterConfiguration 报告路径' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:ConfigPath = Join-Path $script:RepoRoot 'PesterConfiguration.ps1'
        $script:ExpectedReportDirectory = Join-Path $script:RepoRoot 'tests/reports'
        $script:OriginalResultPath = [Environment]::GetEnvironmentVariable('PESTER_RESULT_PATH', 'Process')
    }

    AfterAll {
        [Environment]::SetEnvironmentVariable('PESTER_RESULT_PATH', $script:OriginalResultPath, 'Process')
    }

    BeforeEach {
        Remove-Item Env:\PESTER_RESULT_PATH -ErrorAction SilentlyContinue
    }

    It '从不同工作目录加载时使用相同的默认报告目录' {
        $rootConfig = & $script:ConfigPath
        Push-Location (Join-Path $script:RepoRoot 'psutils')
        try {
            $subdirectoryConfig = & $script:ConfigPath
        }
        finally {
            Pop-Location
        }

        $rootConfig.TestResult.OutputPath.Value | Should -Be (Join-Path $script:ExpectedReportDirectory 'testResults.xml')
        $subdirectoryConfig.TestResult.OutputPath.Value | Should -Be $rootConfig.TestResult.OutputPath.Value
        $rootConfig.CodeCoverage.OutputPath.Value | Should -Be (Join-Path $script:ExpectedReportDirectory 'coverage.xml')
        $rootConfig.CodeCoverage.OutputFormat.Value | Should -Be 'JaCoCo'
        $subdirectoryConfig.CodeCoverage.OutputPath.Value | Should -Be $rootConfig.CodeCoverage.OutputPath.Value
        $script:ExpectedReportDirectory | Should -Exist
    }

    It '保留 PESTER_RESULT_PATH 显式覆盖能力' {
        $overridePath = Join-Path $TestDrive 'custom-results.xml'
        [Environment]::SetEnvironmentVariable('PESTER_RESULT_PATH', $overridePath, 'Process')

        $config = & $script:ConfigPath

        $config.TestResult.OutputPath.Value | Should -Be $overridePath
    }
}

Describe 'PesterConfiguration 并行保护' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:ConfigPath = Join-Path $script:RepoRoot 'PesterConfiguration.ps1'
        $script:OriginalParallel = [Environment]::GetEnvironmentVariable('PWSH_TEST_PARALLEL', 'Process')
        $script:OriginalThrottle = [Environment]::GetEnvironmentVariable('PWSH_TEST_PARALLEL_THROTTLE', 'Process')
        $script:OriginalCoverage = [Environment]::GetEnvironmentVariable('PWSH_TEST_ENABLE_COVERAGE', 'Process')
        $script:OriginalIncludeSlow = [Environment]::GetEnvironmentVariable('PWSH_TEST_INCLUDE_SLOW', 'Process')
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_PARALLEL', $script:OriginalParallel, 'Process')
        [Environment]::SetEnvironmentVariable('PWSH_TEST_PARALLEL_THROTTLE', $script:OriginalThrottle, 'Process')
        [Environment]::SetEnvironmentVariable('PWSH_TEST_ENABLE_COVERAGE', $script:OriginalCoverage, 'Process')
        [Environment]::SetEnvironmentVariable('PWSH_TEST_INCLUDE_SLOW', $script:OriginalIncludeSlow, 'Process')
    }

    It '拒绝 coverage 与文件级并行同时启用' {
        $env:PWSH_TEST_PARALLEL = 'true'
        $env:PWSH_TEST_ENABLE_COVERAGE = 'true'

        { & $script:ConfigPath } | Should -Throw '*CodeCoverage*退回串行*'
    }

    It '拒绝无效并行上限' {
        $env:PWSH_TEST_PARALLEL = 'true'
        $env:PWSH_TEST_ENABLE_COVERAGE = 'false'
        $env:PWSH_TEST_PARALLEL_THROTTLE = 'invalid'

        { & $script:ConfigPath } | Should -Throw '*必须为 0 到 128 的整数*'
    }

    It 'IncludeSlow 移除默认 Slow 排除标签' {
        $env:PWSH_TEST_INCLUDE_SLOW = 'true'

        $config = & $script:ConfigPath

        @($config.Filter.ExcludeTag.Value) | Should -Not -Contain 'Slow'
    }
}
