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
        Set-Content -LiteralPath (Join-Path $script:TestRepo '.pester-version') -Value '6.1.0'
        $script:OriginalWrapperPath = [Environment]::GetEnvironmentVariable('INVOKE_PESTER_MODE_TEST_WRAPPER', 'Process')
        [Environment]::SetEnvironmentVariable('INVOKE_PESTER_MODE_TEST_WRAPPER', $script:WrapperTarget, 'Process')
        @'
function global:Invoke-Pester {
    param($Configuration)
    if ($env:INVOKE_PESTER_MODE_CAPTURE_COVERAGE -eq 'true') {
        return $env:PWSH_TEST_ENABLE_COVERAGE
    }
    if ($env:INVOKE_PESTER_MODE_CAPTURE_PARALLEL -eq 'true') {
        return "$env:PWSH_TEST_ENABLE_COVERAGE|$env:PWSH_TEST_PARALLEL|$env:PWSH_TEST_PARALLEL_THROTTLE|$env:PESTER_COVERAGE_PATH"
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
    Name = 'NoImportedPesterLeak'
    Value = [string]([bool](Get-Module -Name Pester))
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

$env:INVOKE_PESTER_MODE_CAPTURE_PARALLEL = 'true'
$results.Add([pscustomobject]@{
    Name = 'ParallelCoverage'
    Value = (& $env:INVOKE_PESTER_MODE_TEST_WRAPPER -Mode full -Coverage On -CoveragePath './tests/reports/parallel-coverage.xml' -PesterVersion '6.1.0' -Parallel -ParallelThrottle 4 | Out-String).Trim()
})
$results.Add([pscustomobject]@{
    Name = 'RestoredEnvironment'
    Value = "$env:PWSH_TEST_ENABLE_COVERAGE|$env:PWSH_TEST_PARALLEL|$env:PWSH_TEST_PARALLEL_THROTTLE|$env:PESTER_COVERAGE_PATH"
})
Remove-Item Env:\INVOKE_PESTER_MODE_CAPTURE_PARALLEL
foreach ($case in @(
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
        ($results | Where-Object Name -eq 'NoImportedPesterLeak').Value | Should -Be 'False'
        ($results | Where-Object Name -eq 'RestoredEnvironment').Value | Should -Be 'false|||'

        $unsupportedOutput = & pwsh -NoProfile -File $script:WrapperTarget -Mode full -Coverage Off -PesterVersion 5.7.1 -Parallel 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        $unsupportedOutput | Should -Match '不支持 Run\.Parallel'
        ($results | Where-Object Name -eq 'MissingVersion').Value | Should -Match '未安装 Pester 99\.99\.99'
    }

    It '已加载不同 Pester 版本时要求独立进程' {
        $command = @'
Import-Module Pester -RequiredVersion 5.7.1 -Force
& $env:INVOKE_PESTER_MODE_TEST_WRAPPER -Mode qa -PesterVersion '6.1.0'
'@

        $output = & pwsh -NoProfile -Command $command 2>&1 | Out-String

        $LASTEXITCODE | Should -Not -Be 0
        $output | Should -Match '当前进程已加载 Pester 5\.7\.1'
        $output | Should -Match '独立 pwsh 进程'
    }

    It 'Pester 6.0.1 已加载时明确拒绝并行 coverage' {
        $wrapperContent = Get-Content -LiteralPath $script:WrapperTarget -Raw
        $wrapperContent = $wrapperContent.Replace("Import-PinnedPester -Version `$effectivePesterVersion | Out-Null", "function New-PesterConfiguration { [pscustomobject]@{ Run = [pscustomobject]@{ Parallel = `$false } } }")
        Set-Content -LiteralPath $script:WrapperTarget -Value $wrapperContent

        { & $script:WrapperTarget -Mode full -Coverage On -PesterVersion '6.0.1' -Parallel } |
            Should -Throw '*不支持并行 coverage*6.1.0*'
    }
}

Describe 'Install-Pester PSResourceGet bootstrap' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:InstallerSource = Join-Path $script:RepoRoot 'scripts/pwsh/devops/Install-Pester.ps1'
    }

    BeforeEach {
        $script:TestRepo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:InstallerTarget = Join-Path $script:TestRepo 'scripts/pwsh/devops/Install-Pester.ps1'
        New-Item -ItemType Directory -Path (Split-Path -Parent $script:InstallerTarget) -Force | Out-Null
        Copy-Item -LiteralPath $script:InstallerSource -Destination $script:InstallerTarget
        Set-Content -LiteralPath (Join-Path $script:TestRepo '.pester-version') -Value '6.1.0'
    }

    It '已安装精确版本时保持幂等' {
        Mock Get-Module { [pscustomobject]@{ Version = [version]'6.1.0' } } -ParameterFilter { $ListAvailable -and $Name -eq 'Pester' }
        Mock Install-PSResource { }

        & $script:InstallerTarget

        Should -Invoke Install-PSResource -Times 0 -Exactly
    }

    It '缺失时读取单一版本源并传递精确 PSResourceGet 参数' {
        Mock Get-Module { @() } -ParameterFilter { $ListAvailable -and $Name -eq 'Pester' }
        Mock Install-PSResource { }

        & $script:InstallerTarget -Scope AllUsers

        Should -Invoke Install-PSResource -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Pester' -and
            $Version -eq '6.1.0' -and
            $Scope -eq 'AllUsers' -and
            -not $Reinstall -and
            $ErrorAction -eq 'Stop'
        }
    }
}

Describe 'Pester 版本与 package scripts 合同' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:Package = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'package.json') -Raw | ConvertFrom-Json
    }

    It '以 .pester-version 作为 6.1.0 单一默认版本源并保留 5.7.1 回退' {
        (Get-Content -LiteralPath (Join-Path $script:RepoRoot '.pester-version') -Raw).Trim() | Should -Be '6.1.0'
        $script:Package.scripts.'pester:install' | Should -Not -Match '6\.1\.0'
        $script:Package.scripts.'pester:install:pester5' | Should -Match '-Version 5\.7\.1'
        $script:Package.scripts.'test:pwsh:full:pester5' | Should -Match '-PesterVersion 5\.7\.1'
    }

    It '默认 full 保持串行并提供原生并行 coverage PoC 薄入口' {
        $script:Package.scripts.'test:pwsh:full' | Should -Be 'pnpm test:pwsh:full:serial'
        $script:Package.scripts.'test:pwsh:full:serial' | Should -Match 'Invoke-PesterMode\.ps1 -Mode full -Coverage On$'
        $script:Package.scripts.'test:pwsh:coverage:parallel:poc' | Should -Match 'pester-duration-report\.mjs'
        $script:Package.scripts.'test:pwsh:coverage:parallel:poc' | Should -Match 'Invoke-PesterMode\.ps1 -Mode full -Coverage On -Parallel -ParallelThrottle 2'
    }
}

Describe '活动 PowerShell 模块安装入口合同' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    }

    It '活动生产代码不再直接调用旧模块安装命令' {
        $activePaths = @(
            (Join-Path $script:RepoRoot 'psutils')
            (Join-Path $script:RepoRoot 'profile')
            (Join-Path $script:RepoRoot 'scripts')
            (Join-Path $script:RepoRoot 'install.ps1')
        )
        $violations = [System.Collections.Generic.List[string]]::new()

        foreach ($activePath in $activePaths) {
            $files = if (Test-Path -LiteralPath $activePath -PathType Leaf) {
                @(Get-Item -LiteralPath $activePath)
            }
            else {
                @(Get-ChildItem -LiteralPath $activePath -Recurse -File -Include '*.ps1', '*.psm1')
            }
            foreach ($file in $files) {
                $tokens = $null
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
                foreach ($commandAst in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                    if ($commandAst.GetCommandName() -eq ('Install' + '-Module')) {
                        $violations.Add($file.FullName)
                    }
                }
            }
        }

        $violations | Should -BeNullOrEmpty
    }

    It 'misc 安装入口转发固定 Pester 安装脚本且 pslint 使用 PSResourceGet' {
        $miscInstall = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/pwsh/misc/install.ps1') -Raw
        $pslint = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/pwsh/misc/pslint.ps1') -Raw

        $miscInstall | Should -Match "Install-Pester\.ps1"
        $pslint | Should -Match 'Install-PSResource\s+-Name\s+PSScriptAnalyzer\s+-Scope\s+CurrentUser\s+-ErrorAction\s+Stop'
        $pslint | Should -Not -Match '\s-Reinstall(?:\s|$)'
    }
}
