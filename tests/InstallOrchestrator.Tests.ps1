Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts/pwsh/install/InstallOrchestrator.psm1'
    $script:RegistryPath = Join-Path $script:RepoRoot 'config/install/steps.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Install orchestrator registry' {
    It 'loads the ordered Stage 1 catalog' {
        $registry = Import-InstallStepRegistry -Path $script:RegistryPath

        $registry.SchemaVersion | Should -Be 1
        @($registry.Steps).Count | Should -Be 10
        @($registry.Steps.Id) | Should -Be @(
            'sources',
            'shell',
            'core-cli',
            'fonts',
            'profile-tools',
            'full-apps',
            'platform-automation',
            'login-items',
            'desktop-integration',
            'verify'
        )
    }

    It 'selects the Core preset in stable number order' {
        $registry = Import-InstallStepRegistry -Path $script:RegistryPath
        $plan = Select-InstallStepPlan -Registry $registry -Preset Core

        @($plan.Id) | Should -Be @('sources', 'shell', 'core-cli', 'fonts', 'profile-tools', 'verify')
        @($plan.Number) | Should -Be @('03', '04', '05', '06', '07', '99')
    }

    It 'selects every Stage 1 step for Full' {
        $registry = Import-InstallStepRegistry -Path $script:RegistryPath
        $plan = Select-InstallStepPlan -Registry $registry -Preset Full

        @($plan.Id) | Should -Be @($registry.Steps.Id)
    }

    It 'runs an explicit step without expanding dependencies' {
        $registry = Import-InstallStepRegistry -Path $script:RegistryPath
        $plan = Select-InstallStepPlan -Registry $registry -Preset Core -Step @('profile-tools')

        @($plan.Id) | Should -Be @('profile-tools')
        $plan[0].DependenciesVerifiedInRun | Should -BeFalse
    }

    It 'selects the preset tail for FromStep' {
        $registry = Import-InstallStepRegistry -Path $script:RegistryPath
        $plan = Select-InstallStepPlan -Registry $registry -Preset Core -FromStep fonts

        @($plan.Id) | Should -Be @('fonts', 'profile-tools', 'verify')
        @($plan.DependenciesVerifiedInRun | Select-Object -Unique) | Should -Be @($true)
    }

    It 'rejects unknown step identifiers before execution' {
        $registry = Import-InstallStepRegistry -Path $script:RegistryPath

        { Select-InstallStepPlan -Registry $registry -Preset Core -Step @('missing-step') } |
            Should -Throw '*未知安装步骤*'
    }

    It 'rejects duplicate identifiers and numbers' {
        $duplicateIdRegistry = Import-PowerShellDataFile -LiteralPath $script:RegistryPath
        $duplicateIdRegistry.Steps[1].Id = 'sources'
        $duplicateNumberRegistry = Import-PowerShellDataFile -LiteralPath $script:RegistryPath
        $duplicateNumberRegistry.Steps[1].Number = '03'

        { Test-InstallStepRegistry -Registry $duplicateIdRegistry } | Should -Throw '*ID 重复*'
        { Test-InstallStepRegistry -Registry $duplicateNumberRegistry } | Should -Throw '*编号重复*'
    }

    It 'rejects unknown dependencies and dependency cycles' {
        $unknownDependencyRegistry = Import-PowerShellDataFile -LiteralPath $script:RegistryPath
        $unknownDependencyRegistry.Steps[2].DependsOn = @('missing-step')
        $cyclicRegistry = Import-PowerShellDataFile -LiteralPath $script:RegistryPath
        $cyclicRegistry.Steps[0].DependsOn = @('profile-tools')

        { Test-InstallStepRegistry -Registry $unknownDependencyRegistry } | Should -Throw '*未知依赖*'
        { Test-InstallStepRegistry -Registry $cyclicRegistry } | Should -Throw '*循环*'
    }

    It 'rejects unknown runners and missing supported paths' {
        $unknownRunnerRegistry = Import-PowerShellDataFile -LiteralPath $script:RegistryPath
        $unknownRunnerRegistry.Steps[0].Platforms.macos.Runner = 'fish'
        $missingPathRegistry = Import-PowerShellDataFile -LiteralPath $script:RegistryPath
        $missingPathRegistry.Steps[0].Platforms.macos.Path = ''

        { Test-InstallStepRegistry -Registry $unknownRunnerRegistry } | Should -Throw '*未知 Runner*'
        { Test-InstallStepRegistry -Registry $missingPathRegistry } | Should -Throw '*缺少 Path*'
    }
}

Describe 'Install orchestrator execution' {
    BeforeEach {
        $script:FixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("install-orchestrator-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:FixtureRoot -Force | Out-Null

        $script:FixtureSteps = @('sources', 'shell', 'core-cli', 'fonts', 'profile-tools', 'verify')
        foreach ($stepId in $script:FixtureSteps) {
            $scriptPath = Join-Path $script:FixtureRoot ("{0}.ps1" -f $stepId)
            $sourceOutput = if ($stepId -eq 'sources') {
                @'
$effectiveTransactionId = if ($NetworkMode -eq 'Direct') { '' } else { $TransactionId }
$document = [pscustomobject]@{
    ExitCode      = 0
    TransactionId = $effectiveTransactionId
    Rollback      = if ($effectiveTransactionId) { "restore:$effectiveTransactionId" } else { '' }
    Results       = @([pscustomobject]@{ Status = 'Applied' })
}
$document | ConvertTo-Json -Depth 5 -Compress
'@
            }
            else {
                "Write-Output '$stepId-ok'"
            }
            $scriptContent = @"
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]`$NetworkMode,
    [string]`$TransactionId,
    [string]`$OutputFormat,
    [string]`$Preset,
    [switch]`$Unattended,
    [switch]`$NonInteractive
)
$sourceOutput
if (`$env:INSTALL_FIXTURE_FAIL_STEP -eq '$stepId') {
    [Console]::Error.WriteLine('$stepId-failed')
    exit 1
}
if (`$env:INSTALL_FIXTURE_BLOCK_STEP -eq '$stepId') {
    [Console]::Error.WriteLine('$stepId-blocked')
    exit 10
}
exit 0
"@
            Set-Content -LiteralPath $scriptPath -Value $scriptContent -Encoding utf8NoBOM
        }

        $restoreDirectory = Join-Path $script:FixtureRoot 'scripts/pwsh/misc'
        New-Item -ItemType Directory -Path $restoreDirectory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $restoreDirectory 'Switch-Mirrors.ps1') -Encoding utf8NoBOM -Value @'
param(
    [string]$Action,
    [string]$TransactionId,
    [string]$OutputFormat
)
if ($env:INSTALL_FIXTURE_RESTORE_LOG) {
    $TransactionId | Add-Content -LiteralPath $env:INSTALL_FIXTURE_RESTORE_LOG -Encoding utf8NoBOM
}
$exitCode = if ($env:INSTALL_FIXTURE_RESTORE_EXIT) { [int]$env:INSTALL_FIXTURE_RESTORE_EXIT } else { 0 }
[pscustomobject]@{
    ExitCode      = $exitCode
    TransactionId = $TransactionId
    Results       = @([pscustomobject]@{ Status = if ($exitCode -eq 0) { 'Restored' } else { 'RestoreFailed' } })
} | ConvertTo-Json -Depth 5 -Compress
exit $exitCode
'@

        $script:FixtureRegistry = @{
            SchemaVersion = 1
            Steps         = @(
                @{ Id = 'sources'; Number = '03'; Presets = @('Core', 'Full'); DependsOn = @(); Platforms = @{} },
                @{ Id = 'shell'; Number = '04'; Presets = @('Core', 'Full'); DependsOn = @(); Platforms = @{} },
                @{ Id = 'core-cli'; Number = '05'; Presets = @('Core', 'Full'); DependsOn = @('sources'); Platforms = @{} },
                @{ Id = 'fonts'; Number = '06'; Presets = @('Core', 'Full'); DependsOn = @('sources'); Platforms = @{} },
                @{ Id = 'profile-tools'; Number = '07'; Presets = @('Core', 'Full'); DependsOn = @('core-cli'); Platforms = @{} },
                @{ Id = 'verify'; Number = '99'; Presets = @('Core', 'Full'); DependsOn = @(); Platforms = @{} }
            )
        }
        foreach ($stepDefinition in $script:FixtureRegistry.Steps) {
            $entry = @{
                Supported       = $true
                Path            = ("{0}.ps1" -f $stepDefinition.Id)
                Runner          = 'pwsh'
                PreviewArgument = '-WhatIf'
            }
            $stepDefinition.Platforms = @{
                macos   = $entry.Clone()
                linux   = $entry.Clone()
                windows = $entry.Clone()
            }
        }
        $null = Test-InstallStepRegistry -Registry $script:FixtureRegistry
        Remove-Item Env:\INSTALL_FIXTURE_FAIL_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_BLOCK_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_RESTORE_EXIT -ErrorAction SilentlyContinue
        $script:RestoreLog = Join-Path $script:FixtureRoot 'restore.log'
        $env:INSTALL_FIXTURE_RESTORE_LOG = $script:RestoreLog
    }

    AfterEach {
        Remove-Item Env:\INSTALL_FIXTURE_FAIL_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_BLOCK_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_RESTORE_EXIT -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_RESTORE_LOG -ErrorAction SilentlyContinue
        if ($script:FixtureRoot -and (Test-Path -LiteralPath $script:FixtureRoot)) {
            Remove-Item -LiteralPath $script:FixtureRoot -Recurse -Force
        }
    }

    It 'executes a successful Core plan in stable order' {
        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform macos `
            -Preset Core

        $document.Status | Should -Be 'Succeeded'
        $document.ExitCode | Should -Be 0
        @($document.Results.Id) | Should -Be $script:FixtureSteps
        @($document.Results.Status | Select-Object -Unique) | Should -Be @('Succeeded')
    }

    It 'blocks source dependents but continues independent steps' {
        $env:INSTALL_FIXTURE_FAIL_STEP = 'sources'

        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform linux `
            -Preset Core

        $document.Status | Should -Be 'Failed'
        $document.ExitCode | Should -Be 1
        ($document.Results | Where-Object Id -eq 'sources').Status | Should -Be 'Failed'
        ($document.Results | Where-Object Id -eq 'shell').Status | Should -Be 'Succeeded'
        ($document.Results | Where-Object Id -eq 'core-cli').Status | Should -Be 'Blocked'
        ($document.Results | Where-Object Id -eq 'fonts').Status | Should -Be 'Blocked'
        ($document.Results | Where-Object Id -eq 'profile-tools').Status | Should -Be 'Blocked'
        ($document.Results | Where-Object Id -eq 'verify').Status | Should -Be 'Succeeded'
    }

    It 'returns Blocked when a supported leaf is missing' {
        Remove-Item -LiteralPath (Join-Path $script:FixtureRoot 'sources.ps1') -Force

        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform windows `
            -Preset Core

        $document.Status | Should -Be 'Blocked'
        $document.ExitCode | Should -Be 10
        ($document.Results | Where-Object Id -eq 'sources').Message | Should -Match '不存在'
    }

    It 'executes an exact step without requiring selected dependencies' {
        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform macos `
            -Preset Core `
            -Step @('profile-tools')

        $document.ExitCode | Should -Be 0
        @($document.Results.Id) | Should -Be @('profile-tools')
        $document.Results[0].DependenciesVerifiedInRun | Should -BeFalse
    }

    It 'marks successful WhatIf steps as Preview' {
        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform macos `
            -Preset Core `
            -Preview

        $document.ExitCode | Should -Be 0
        @($document.Results.Status | Select-Object -Unique) | Should -Be @('Preview')
        $document.SourceRestore.Attempted | Should -BeFalse
    }

    It 'does not create a source transaction in Direct mode' {
        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform macos `
            -Preset Core `
            -NetworkMode Direct

        $document.SourceTransactionId | Should -BeNullOrEmpty
        $document.SourceRestore.Status | Should -Be 'NotRequired'
        Test-Path -LiteralPath $script:RestoreLog | Should -BeFalse
    }

    It 'keeps a China transaction active and returns its rollback command' {
        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform macos `
            -Preset Core `
            -NetworkMode China

        $document.Status | Should -Be 'Succeeded'
        $document.SourceTransactionId | Should -Not -BeNullOrEmpty
        $document.Rollback | Should -Match $document.SourceTransactionId
        $document.SourceRestore.Attempted | Should -BeFalse
    }

    It 'restores an Auto transaction after a successful run' {
        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform linux `
            -Preset Core `
            -NetworkMode Auto

        $document.Status | Should -Be 'Succeeded'
        $document.SourceRestore.Status | Should -Be 'Succeeded'
        $document.Rollback | Should -BeNullOrEmpty
        (Get-Content -LiteralPath $script:RestoreLog -Raw).Trim() | Should -Be $document.SourceTransactionId
    }

    It 'restores an Auto transaction when the source step fails after creating it' {
        $env:INSTALL_FIXTURE_FAIL_STEP = 'sources'

        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform windows `
            -Preset Core `
            -NetworkMode Auto

        $document.Status | Should -Be 'Failed'
        $document.SourceRestore.Status | Should -Be 'Succeeded'
        (Get-Content -LiteralPath $script:RestoreLog -Raw).Trim() | Should -Be $document.SourceTransactionId
    }

    It 'raises a successful run to Blocked when Auto restore fails' {
        $env:INSTALL_FIXTURE_RESTORE_EXIT = '1'

        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform macos `
            -Preset Core `
            -NetworkMode Auto

        $document.Status | Should -Be 'Blocked'
        $document.ExitCode | Should -Be 10
        $document.SourceRestore.Status | Should -Be 'Blocked'
        $document.Rollback | Should -Match 'Switch-Mirrors.ps1 -Action Restore'
    }

    It 'preserves the original Failed status when Auto restore also fails' {
        $env:INSTALL_FIXTURE_FAIL_STEP = 'core-cli'
        $env:INSTALL_FIXTURE_RESTORE_EXIT = '1'

        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform linux `
            -Preset Core `
            -NetworkMode Auto

        $document.Status | Should -Be 'Failed'
        $document.ExitCode | Should -Be 1
        $document.SourceRestore.Status | Should -Be 'Blocked'
    }

    It 'maps leaf exit 10 and skipped dependencies to Blocked while continuing verify' {
        $env:INSTALL_FIXTURE_BLOCK_STEP = 'sources'

        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform linux `
            -Preset Core `
            -SkipStep @('shell')

        $document.Status | Should -Be 'Blocked'
        $document.ExitCode | Should -Be 10
        ($document.Results | Where-Object Id -eq 'sources').Status | Should -Be 'Blocked'
        ($document.Results | Where-Object Id -eq 'verify').Status | Should -Be 'Succeeded'
        @($document.Results.Id) | Should -Not -Contain 'shell'
    }

    It 'returns Step and FromStep retry commands with the run mode' {
        $env:INSTALL_FIXTURE_FAIL_STEP = 'core-cli'

        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform macos `
            -Preset Core `
            -NetworkMode China `
            -NonInteractive

        ($document.Results | Where-Object Id -eq 'core-cli').RerunCommand |
            Should -Be './install.ps1 -Preset Core -Step core-cli -NetworkMode China -NonInteractive'
        $document.ContinueCommand |
            Should -Be './install.ps1 -Preset Core -FromStep core-cli -NetworkMode China -NonInteractive'
    }
}
