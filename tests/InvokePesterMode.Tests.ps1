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
        Set-Content -LiteralPath (Join-Path $script:TestRepo '.pester-version') -Value '5.7.1'
        $script:OriginalWrapperPath = [Environment]::GetEnvironmentVariable('INVOKE_PESTER_MODE_TEST_WRAPPER', 'Process')
        [Environment]::SetEnvironmentVariable('INVOKE_PESTER_MODE_TEST_WRAPPER', $script:WrapperTarget, 'Process')
        @'
function global:Invoke-Pester {
    param($Configuration)
    if ($env:INVOKE_PESTER_MODE_CAPTURE_COVERAGE -eq 'true') {
        return $env:PWSH_TEST_ENABLE_COVERAGE
    }
    $env:PWSH_TEST_PATH
}
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

    It '在一个隔离进程中验证路径、版本缺失与并行保护合同' {
        $command = @'
$results = [System.Collections.Generic.List[object]]::new()

$env:PWSH_TEST_PATH = './tests/inherited.Tests.ps1'
$results.Add([pscustomobject]@{
    Name = 'InheritedPath'
    Value = (& $env:INVOKE_PESTER_MODE_TEST_WRAPPER -Mode qa | Out-String).Trim()
})

$results.Add([pscustomobject]@{
    Name = 'ExplicitPath'
    Value = (& $env:INVOKE_PESTER_MODE_TEST_WRAPPER -Mode qa -Path './tests/explicit.Tests.ps1' | Out-String).Trim()
})

$env:PWSH_TEST_ENABLE_COVERAGE = 'false'
$env:INVOKE_PESTER_MODE_CAPTURE_COVERAGE = 'true'
$results.Add([pscustomobject]@{
    Name = 'DefaultCoverage'
    Value = (& $env:INVOKE_PESTER_MODE_TEST_WRAPPER -Mode full | Out-String).Trim()
})
Remove-Item Env:\INVOKE_PESTER_MODE_CAPTURE_COVERAGE

foreach ($case in @(
    @{ Name = 'UnsupportedParallel'; Arguments = @{ Mode = 'full'; Coverage = 'Off'; PesterVersion = '5.7.1'; Parallel = $true } }
    @{ Name = 'MissingVersion'; Arguments = @{ Mode = 'full'; Coverage = 'Off'; PesterVersion = '99.99.99' } }
)) {
    try {
        $caseArguments = $case.Arguments
        & $env:INVOKE_PESTER_MODE_TEST_WRAPPER @caseArguments | Out-Null
        $message = ''
    }
    catch {
        $message = $_.Exception.Message
    }
    $results.Add([pscustomobject]@{ Name = $case.Name; Value = $message })
}

$results | ConvertTo-Json -Compress
'@

        $output = & pwsh -NoProfile -Command $command 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 0 -Because $output
        $results = @($output | ConvertFrom-Json)
        ($results | Where-Object Name -eq 'InheritedPath').Value | Should -Be './tests/inherited.Tests.ps1'
        ($results | Where-Object Name -eq 'ExplicitPath').Value | Should -Be './tests/explicit.Tests.ps1'
        ($results | Where-Object Name -eq 'DefaultCoverage').Value | Should -Be 'false'
        ($results | Where-Object Name -eq 'UnsupportedParallel').Value | Should -Match '不支持 Run\.Parallel'
        ($results | Where-Object Name -eq 'MissingVersion').Value | Should -Match '未安装 Pester 99\.99\.99'
    }
}
