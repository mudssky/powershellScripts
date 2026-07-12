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
