Describe 'PesterConfiguration 报告路径' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:ConfigPath = Join-Path $script:RepoRoot 'PesterConfiguration.ps1'
        $script:ExpectedReportDirectory = Join-Path $script:RepoRoot 'tests/reports'
        $script:OriginalResultPath = [Environment]::GetEnvironmentVariable('PESTER_RESULT_PATH', 'Process')
        $script:OriginalCoveragePath = [Environment]::GetEnvironmentVariable('PESTER_COVERAGE_PATH', 'Process')
    }

    AfterAll {
        [Environment]::SetEnvironmentVariable('PESTER_RESULT_PATH', $script:OriginalResultPath, 'Process')
        [Environment]::SetEnvironmentVariable('PESTER_COVERAGE_PATH', $script:OriginalCoveragePath, 'Process')
    }

    BeforeEach {
        Remove-Item Env:\PESTER_RESULT_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\PESTER_COVERAGE_PATH -ErrorAction SilentlyContinue
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

    It '保留 PESTER_COVERAGE_PATH 唯一 coverage 路径覆盖能力' {
        $overridePath = Join-Path $TestDrive 'custom-coverage.xml'
        [Environment]::SetEnvironmentVariable('PESTER_COVERAGE_PATH', $overridePath, 'Process')

        $config = & $script:ConfigPath

        $config.CodeCoverage.OutputPath.Value | Should -Be $overridePath
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

    It '按已加载版本能力处理 coverage 与文件级并行组合' {
        $env:PWSH_TEST_PARALLEL = 'true'
        $env:PWSH_TEST_ENABLE_COVERAGE = 'true'
        $env:PWSH_TEST_PARALLEL_THROTTLE = '2'
        $loadedVersion = (Get-Module -Name Pester | Select-Object -First 1).Version

        if ($loadedVersion -ge [version]'6.1.0') {
            $config = & $script:ConfigPath
            $config.Run.Parallel.Value | Should -BeTrue
            $config.Run.ParallelThrottleLimit.Value | Should -Be 2
            $config.CodeCoverage.Enabled.Value | Should -BeTrue
        }
        else {
            { & $script:ConfigPath } | Should -Throw '*不支持*'
        }
    }

    It '旧 Pester 版本明确拒绝并行 coverage' {
        $env:PWSH_TEST_PARALLEL = 'true'
        $env:PWSH_TEST_ENABLE_COVERAGE = 'true'
        Mock Get-Module { [pscustomobject]@{ Version = [version]'6.0.1' } } -ParameterFilter { $Name -eq 'Pester' }

        { & $script:ConfigPath } | Should -Throw '*不支持并行 coverage*6.1.0*'
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
