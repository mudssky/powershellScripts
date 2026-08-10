Set-StrictMode -Version Latest
BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:ToolRoot = Join-Path $script:RepoRoot 'scripts/pwsh/devops/browser-control'
    $env:PWSH_TEST_SKIP_BROWSER_CONTROL_MAIN = '1'
    . (Join-Path $script:ToolRoot 'main.ps1')
}
AfterAll { Remove-Item Env:\PWSH_TEST_SKIP_BROWSER_CONTROL_MAIN -ErrorAction SilentlyContinue }

Describe 'browserctl manifest' {
    It 'exposes one generated shim entry' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:ToolRoot 'tool.psd1')
        $manifest.BinName | Should -Be 'browserctl.ps1'
        $manifest.Entry | Should -Be 'main.ps1'
    }
}

Describe 'browserctl dispatch' {
    BeforeEach { Mock Invoke-BrowserHostControl { [pscustomobject]@{ ExitCode = 0 } } }

    It 'passes stable start and attach argv' {
        Invoke-BrowserControlCommand -Action start -Target wsl | Out-Null
        Should -Invoke Invoke-BrowserHostControl -ParameterFilter { $Arguments -join ' ' -eq 'start -Runtime wsl' }
        Invoke-BrowserControlCommand -Action attach -Target playwright | Out-Null
        Should -Invoke Invoke-BrowserHostControl -ParameterFilter { $Arguments -join ' ' -eq 'attach -Client playwright' }
    }

    It 'keeps stop thin and requires owner recovery confirmation' {
        Invoke-BrowserControlCommand -Action stop | Out-Null
        Should -Invoke Invoke-BrowserHostControl -ParameterFilter { $Arguments.Count -eq 1 -and $Arguments[0] -eq 'stop' }
        { Invoke-BrowserControlCommand -Action recover-owner } | Should -Throw '*ConfirmServiceName browser-runtime*'
        Invoke-BrowserControlCommand -Action recover-owner -ConfirmServiceName browser-runtime | Out-Null
        Should -Invoke Invoke-BrowserHostControl -ParameterFilter { $Arguments -join ' ' -eq 'recover-owner -ConfirmServiceName browser-runtime' }
    }

    It 'rejects invalid targets before invoking host control' {
        { Invoke-BrowserControlCommand -Action start -Target linux } | Should -Throw
        Should -Invoke Invoke-BrowserHostControl -Times 0
    }
}

Describe 'installed helper boundary' {
    It 'returns 127 when browser-host is missing' {
        (Invoke-BrowserHostControl -Arguments @('status') -BrowserHostPath (Join-Path $TestDrive 'missing.ps1')).ExitCode | Should -Be 127
    }
}
