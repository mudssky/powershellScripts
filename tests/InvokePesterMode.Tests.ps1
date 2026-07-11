Describe 'Invoke-PesterMode 测试路径传递' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:WrapperSource = Join-Path $script:RepoRoot 'scripts/pwsh/devops/Invoke-PesterMode.ps1'
    }

    BeforeEach {
        $script:TestRepo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:WrapperTarget = Join-Path $script:TestRepo 'scripts/pwsh/devops/Invoke-PesterMode.ps1'
        New-Item -ItemType Directory -Path (Split-Path -Parent $script:WrapperTarget) -Force | Out-Null
        Copy-Item -LiteralPath $script:WrapperSource -Destination $script:WrapperTarget
        $script:OriginalWrapperPath = [Environment]::GetEnvironmentVariable('INVOKE_PESTER_MODE_TEST_WRAPPER', 'Process')
        [Environment]::SetEnvironmentVariable('INVOKE_PESTER_MODE_TEST_WRAPPER', $script:WrapperTarget, 'Process')
        @'
[pscustomobject]@{
    Run = [pscustomobject]@{
        Exit = $false
    }
}
'@ | Set-Content -LiteralPath (Join-Path $script:TestRepo 'PesterConfiguration.ps1')
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable('INVOKE_PESTER_MODE_TEST_WRAPPER', $script:OriginalWrapperPath, 'Process')
    }

    It '未显式传入 Path 时保留调用方注入的测试路径' {
        $command = @'
$env:PWSH_TEST_PATH = './tests/inherited.Tests.ps1'
function Invoke-Pester {
    param($Configuration)
    $env:PWSH_TEST_PATH
}
& $env:INVOKE_PESTER_MODE_TEST_WRAPPER -Mode qa
'@

        $output = & pwsh -NoProfile -Command $command 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 0 -Because $output
        $output.Trim() | Should -Be './tests/inherited.Tests.ps1'
    }

    It '显式 Path 覆盖调用方已有测试路径' {
        $command = @'
$env:PWSH_TEST_PATH = './tests/inherited.Tests.ps1'
function Invoke-Pester {
    param($Configuration)
    $env:PWSH_TEST_PATH
}
& $env:INVOKE_PESTER_MODE_TEST_WRAPPER -Mode qa -Path './tests/explicit.Tests.ps1'
'@

        $output = & pwsh -NoProfile -Command $command 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 0 -Because $output
        $output.Trim() | Should -Be './tests/explicit.Tests.ps1'
    }
}
