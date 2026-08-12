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
    Results       = @([pscustomobject]@{
        Status   = 'Applied'
        Rollback = if ($effectiveTransactionId) { "restore:$effectiveTransactionId" } else { '' }
    })
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
if (`$env:INSTALL_FIXTURE_DELAY_STEP -eq '$stepId') {
    Start-Sleep -Milliseconds ([int]`$env:INSTALL_FIXTURE_DELAY_MILLISECONDS)
}
if (`$env:INSTALL_FIXTURE_DIAGNOSTIC_STEP -eq '$stepId') {
    1..200 | ForEach-Object { Write-Output ("success-log-{0}: {1}" -f `$_, ('x' * 32)) }
    Write-Output '[Failed] delta: command=scoop install delta; exitCode=1; outputTail=bucket update failed token=fixture-secret'
    exit 1
}
if (`$env:INSTALL_FIXTURE_CHILD_STEP -eq '$stepId') {
    `$childStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    `$childStartInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    `$childStartInfo.UseShellExecute = `$false
    `$childStartInfo.ArgumentList.Add('-NoProfile')
    `$childStartInfo.ArgumentList.Add('-File')
    `$childStartInfo.ArgumentList.Add((Join-Path `$PSScriptRoot 'child-wait.ps1'))
    `$child = [System.Diagnostics.Process]::new()
    `$child.StartInfo = `$childStartInfo
    try {
        if (-not `$child.Start()) {
            throw 'failed to start child fixture'
        }
        `$child.Id | Set-Content -LiteralPath `$env:INSTALL_FIXTURE_CHILD_PID_LOG -Encoding ascii
        `$child.WaitForExit()
    }
    finally {
        `$child.Dispose()
    }
}
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
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'child-wait.ps1') -Encoding utf8NoBOM -Value @'
Start-Sleep -Seconds 60
'@


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
        Remove-Item Env:\INSTALL_FIXTURE_DELAY_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_DELAY_MILLISECONDS -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_CHILD_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_CHILD_PID_LOG -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_DIAGNOSTIC_STEP -ErrorAction SilentlyContinue
        $script:RestoreLog = Join-Path $script:FixtureRoot 'restore.log'
        $env:INSTALL_FIXTURE_RESTORE_LOG = $script:RestoreLog
        $module = Get-Module InstallOrchestrator
        & $module {
            $script:InstallLeafProcessTestCalls = [System.Collections.Generic.List[object]]::new()
            $script:InstallLeafProcessTestHook = {
                param(
                    [string]$Runner,
                    [string]$ScriptPath,
                    [string[]]$ArgumentList,
                    [switch]$ShowProgress,
                    [string]$StepNumber,
                    [string]$StepId
                )

                $script:InstallLeafProcessTestCalls.Add([pscustomobject]@{
                        Runner       = $Runner
                        ScriptPath   = $ScriptPath
                        ArgumentList = @($ArgumentList)
                        ShowProgress = $ShowProgress.IsPresent
                        StepNumber   = $StepNumber
                        StepId       = $StepId
                    })
                $leafName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
                $exitCode = 0
                $stdout = "$leafName-ok"
                $stderr = ''

                if ($leafName -eq 'Switch-Mirrors') {
                    $transactionIndex = [array]::IndexOf($ArgumentList, '-TransactionId')
                    $transactionId = if ($transactionIndex -ge 0) { $ArgumentList[$transactionIndex + 1] } else { '' }
                    if ($env:INSTALL_FIXTURE_RESTORE_LOG) {
                        $transactionId | Add-Content -LiteralPath $env:INSTALL_FIXTURE_RESTORE_LOG -Encoding utf8NoBOM
                    }
                    $exitCode = if ($env:INSTALL_FIXTURE_RESTORE_EXIT) { [int]$env:INSTALL_FIXTURE_RESTORE_EXIT } else { 0 }
                    $stdout = [pscustomobject]@{
                        ExitCode      = $exitCode
                        TransactionId = $transactionId
                        Results       = @([pscustomobject]@{ Status = if ($exitCode -eq 0) { 'Restored' } else { 'RestoreFailed' } })
                    } | ConvertTo-Json -Depth 5 -Compress
                }
                elseif ($leafName -eq 'sources') {
                    $transactionIndex = [array]::IndexOf($ArgumentList, '-TransactionId')
                    $transactionId = if ($transactionIndex -ge 0) { $ArgumentList[$transactionIndex + 1] } else { '' }
                    $networkModeIndex = [array]::IndexOf($ArgumentList, '-NetworkMode')
                    $networkMode = if ($networkModeIndex -ge 0) { $ArgumentList[$networkModeIndex + 1] } else { 'Direct' }
                    $isPreview = $ArgumentList -contains '-WhatIf'
                    $sourceTransactionId = if (-not $isPreview -and $networkMode -in @('China', 'Auto')) { $transactionId } else { '' }
                    $stdout = [pscustomobject]@{
                        ExitCode     = 0
                        TransactionId = $sourceTransactionId
                        Rollback     = if ($sourceTransactionId) { "restore $sourceTransactionId" } else { '' }
                        Results      = @()
                    } | ConvertTo-Json -Depth 5 -Compress
                }

                if ($env:INSTALL_FIXTURE_DIAGNOSTIC_STEP -eq $leafName) {
                    $exitCode = 1
                    $stdout = (1..200 | ForEach-Object { "success-log-$_`: $('x' * 32)" }) -join "`n"
                    $stdout += "`n[Failed] delta: command=scoop install delta; exitCode=1; outputTail=bucket update failed token=fixture-secret"
                }
                if ($env:INSTALL_FIXTURE_FAIL_STEP -eq $leafName) {
                    $exitCode = 1
                    $stderr = "$leafName-failed"
                }
                if ($env:INSTALL_FIXTURE_BLOCK_STEP -eq $leafName) {
                    $exitCode = 10
                    $stderr = "$leafName-blocked"
                }

                return [pscustomobject]@{
                    ExitCode   = $exitCode
                    Stdout     = $stdout
                    Stderr     = $stderr
                    DurationMs = 1
                    Command    = "$Runner $ScriptPath $($ArgumentList -join ' ')".Trim()
                }
            }
        }
    }

    AfterEach {
        $module = Get-Module InstallOrchestrator
        & $module {
            $script:InstallLeafProcessTestHook = $null
            $script:InstallLeafProcessTestCalls = $null
        }
        Remove-Item Env:\INSTALL_FIXTURE_FAIL_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_BLOCK_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_RESTORE_EXIT -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_DELAY_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_DELAY_MILLISECONDS -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_CHILD_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_CHILD_PID_LOG -ErrorAction SilentlyContinue
        Remove-Item Env:\INSTALL_FIXTURE_DIAGNOSTIC_STEP -ErrorAction SilentlyContinue
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
        $module = Get-Module InstallOrchestrator
        $calls = & $module { @($script:InstallLeafProcessTestCalls) }
        @($calls.StepId) | Should -Be $script:FixtureSteps
    }

    It 'process boundary preserves the zsh runner and argument list' {
        $module = Get-Module InstallOrchestrator

        $result = & $module {
            Invoke-InstallLeafProcessBoundary `
                -Runner zsh `
                -ScriptPath '/fixture/leaf.zsh' `
                -ArgumentList @('--preset', 'Full') `
                -ShowProgress `
                -StepNumber '09' `
                -StepId 'platform-automation'
        }

        $result.ExitCode | Should -Be 0
        $call = & $module { @($script:InstallLeafProcessTestCalls)[0] }
        $call.Runner | Should -Be 'zsh'
        $call.ArgumentList | Should -Be @('--preset', 'Full')
        $call.ShowProgress | Should -BeTrue
        $call.StepNumber | Should -Be '09'
        $call.StepId | Should -Be 'platform-automation'
    }

    It 'writes exactly one startup progress line before a long Text step exits' {
        $module = Get-Module InstallOrchestrator
        & $module { $script:InstallLeafProcessTestHook = $null }
        $env:INSTALL_FIXTURE_DELAY_STEP = 'profile-tools'
        $env:INSTALL_FIXTURE_DELAY_MILLISECONDS = '1600'
        $originalError = [Console]::Error
        $writer = [System.IO.StringWriter]::new()
        $powerShell = [powershell]::Create()
        $asyncResult = $null
        try {
            [Console]::SetError($writer)
            $null = $powerShell.AddScript({
                    param($ModulePath, $Registry, $RepoRoot)
                    Import-Module $ModulePath -Force
                    Invoke-InstallOrchestrator `
                        -Registry $Registry `
                        -RepoRoot $RepoRoot `
                        -Platform macos `
                        -Preset Core `
                        -Step @('profile-tools') `
                        -ShowProgress
                }).AddArgument($script:ModulePath).AddArgument($script:FixtureRegistry).AddArgument($script:FixtureRoot)
            $asyncResult = $powerShell.BeginInvoke()

            foreach ($attempt in 1..80) {
                if ($writer.ToString() -match '\[Running\] 07 profile-tools: .*profile-tools\.ps1') {
                    break
                }
                Start-Sleep -Milliseconds 25
            }
            $progressBeforeExit = $writer.ToString()
            $asyncResult.IsCompleted | Should -BeFalse
            $output = $powerShell.EndInvoke($asyncResult)
            $document = @($output)[-1]
        }
        finally {
            if ($null -ne $asyncResult -and -not $asyncResult.IsCompleted) {
                $powerShell.Stop()
                try { $null = $powerShell.EndInvoke($asyncResult) } catch {}
            }
            $powerShell.Dispose()
            [Console]::SetError($originalError)
            $writer.Dispose()
        }

        $document.Status | Should -Be 'Succeeded'
        $progressBeforeExit | Should -Match '\[Running\] 07 profile-tools: .*profile-tools\.ps1'
        $writer.ToString() | Should -Not -Match 'elapsed='
        @([regex]::Matches($writer.ToString(), '\[Running\] 07 profile-tools')).Count | Should -Be 1
    }

    It 'preserves long UTF-8 stdout and stderr across buffer boundaries' {
        $fixturePath = Join-Path $script:FixtureRoot 'utf8-output.ps1'
        Set-Content -LiteralPath $fixturePath -Encoding utf8NoBOM -Value @'
$stdoutText = 'stdout-start|' + ('中文输出-边界|' * 2500) + 'stdout-end'
$stderrText = 'stderr-start|' + ('错误诊断-边界|' * 2500) + 'stderr-end'
[Console]::Out.Write($stdoutText)
[Console]::Error.Write($stderrText)
'@
        $expectedStdout = 'stdout-start|' + ('中文输出-边界|' * 2500) + 'stdout-end'
        $expectedStderr = 'stderr-start|' + ('错误诊断-边界|' * 2500) + 'stderr-end'
        $module = Get-Module InstallOrchestrator

        $result = & $module { param($Path) Invoke-InstallLeafProcess -Runner pwsh -ScriptPath $Path } $fixturePath

        $result.ExitCode | Should -Be 0
        $result.Stdout | Should -BeExactly $expectedStdout
        $result.Stderr | Should -BeExactly $expectedStderr
        $result.Stdout | Should -Not -Match ([char]0xfffd)
        $result.Stderr | Should -Not -Match ([char]0xfffd)
    }

    It 'binds named values and switches through the UTF-8 wrapper and removes it under WhatIf' {
        $fixturePath = Join-Path $script:FixtureRoot 'named-arguments.ps1'
        Set-Content -LiteralPath $fixturePath -Encoding utf8NoBOM -Value @'
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Core', 'Full')]
    [string]$Preset,
    [switch]$Enabled
)
[pscustomobject]@{ Preset = $Preset; Enabled = [bool]$Enabled } | ConvertTo-Json -Compress
'@
        $module = Get-Module InstallOrchestrator
        $temporaryPattern = Join-Path ([System.IO.Path]::GetTempPath()) 'powershellScripts-install-*.ps1'
        $wrappersBefore = @(Get-ChildItem -Path $temporaryPattern -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

        $result = & $module {
            param($Path)
            $WhatIfPreference = $true
            Invoke-InstallLeafProcess -Runner pwsh -ScriptPath $Path -ArgumentList @('-Preset', 'Core', '-Enabled')
        } $fixturePath
        $document = $result.Stdout | ConvertFrom-Json

        $result.ExitCode | Should -Be 0
        $document.Preset | Should -Be 'Core'
        $document.Enabled | Should -BeTrue
        $result.Stdout | Should -Not -Match '^What if:'
        $wrappersAfter = @(Get-ChildItem -Path $temporaryPattern -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        @($wrappersAfter | Where-Object { $_ -notin $wrappersBefore }) | Should -BeNullOrEmpty
    }

    It 'decodes a round-trippable Windows ANSI output fallback without replacement characters' -Skip:(-not $IsWindows) {
        $text = '本地编码诊断'
        $codePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
        $encoding = [System.Text.Encoding]::GetEncoding($codePage)
        $bytes = $encoding.GetBytes($text)
        if ($encoding.GetString($bytes) -ne $text) {
            Set-ItResult -Skipped -Because "ANSI code page $codePage 无法往返中文夹具"
            return
        }
        $module = Get-Module InstallOrchestrator

        $decoded = & $module { param($InputBytes) ConvertFrom-InstallOutputBytes -Bytes $InputBytes } $bytes

        $decoded | Should -BeExactly $text
        $decoded | Should -Not -Match ([char]0xfffd)
    }

    It 'prioritizes a failed item over long successful output and protects secrets' {
        $env:INSTALL_FIXTURE_DIAGNOSTIC_STEP = 'core-cli'

        $document = Invoke-InstallOrchestrator `
            -Registry $script:FixtureRegistry `
            -RepoRoot $script:FixtureRoot `
            -Platform windows `
            -Preset Core `
            -Step @('core-cli')

        $result = $document.Results[0]
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match '\[Failed\] delta:'
        $result.Message | Should -Match 'command=scoop install delta'
        $result.Message | Should -Match 'exitCode=1'
        $result.Message | Should -Match 'token=\[REDACTED\]'
        $result.Message.Length | Should -BeLessOrEqual 1024
        $result.Message | Should -Not -Match 'success-log-1:'
    }

    It 'keeps progress disabled for JSON-oriented calls by default' {
        $originalError = [Console]::Error
        $writer = [System.IO.StringWriter]::new()
        try {
            [Console]::SetError($writer)
            $document = Invoke-InstallOrchestrator `
                -Registry $script:FixtureRegistry `
                -RepoRoot $script:FixtureRoot `
                -Platform macos `
                -Preset Core `
                -Step @('shell')
            $json = ConvertTo-InstallRunJson -Document $document
            $progress = $writer.ToString()
        }
        finally {
            [Console]::SetError($originalError)
            $writer.Dispose()
        }

        $progress | Should -BeNullOrEmpty
        ($json | ConvertFrom-Json).Status | Should -Be 'Succeeded'
    }

    It 'terminates the live child process tree when the orchestrator pipeline is interrupted' {
        $module = Get-Module InstallOrchestrator
        & $module { $script:InstallLeafProcessTestHook = $null }
        $env:INSTALL_FIXTURE_CHILD_STEP = 'profile-tools'
        $childPidLog = Join-Path $script:FixtureRoot 'child.pid'
        $env:INSTALL_FIXTURE_CHILD_PID_LOG = $childPidLog
        $powerShell = [powershell]::Create()
        $asyncResult = $null
        $childPid = 0
        try {
            $null = $powerShell.AddScript({
                    param($ModulePath, $Registry, $RepoRoot)
                    Import-Module $ModulePath -Force
                    Invoke-InstallOrchestrator `
                        -Registry $Registry `
                        -RepoRoot $RepoRoot `
                        -Platform macos `
                        -Preset Core `
                        -Step @('profile-tools')
                }).AddArgument($script:ModulePath).AddArgument($script:FixtureRegistry).AddArgument($script:FixtureRoot)
            $asyncResult = $powerShell.BeginInvoke()
            foreach ($attempt in 1..50) {
                if (Test-Path -LiteralPath $childPidLog) {
                    break
                }
                Start-Sleep -Milliseconds 100
            }
            Test-Path -LiteralPath $childPidLog | Should -BeTrue
            $childPid = [int](Get-Content -LiteralPath $childPidLog -Raw)
            $childProcess = Get-Process -Id $childPid -ErrorAction Stop
            try {
                $childProcess.HasExited | Should -BeFalse
            }
            finally {
                $childProcess.Dispose()
            }

            $powerShell.Stop()
            try { $null = $powerShell.EndInvoke($asyncResult) } catch {}

            $childExited = $false
            foreach ($attempt in 1..50) {
                try {
                    $remainingChild = Get-Process -Id $childPid -ErrorAction Stop
                    $remainingChild.Dispose()
                    Start-Sleep -Milliseconds 100
                }
                catch {
                    $childExited = $true
                    break
                }
            }
            $childExited | Should -BeTrue
        }
        finally {
            if ($null -ne $asyncResult -and -not $asyncResult.IsCompleted) {
                $powerShell.Stop()
                try { $null = $powerShell.EndInvoke($asyncResult) } catch {}
            }
            $powerShell.Dispose()
            if ($childPid -gt 0) {
                try {
                    $remainingChild = Get-Process -Id $childPid -ErrorAction Stop
                    $remainingChild.Kill($true)
                    $remainingChild.Dispose()
                }
                catch {
                }
            }
        }
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

    It 'writes a complete human-readable run summary' {
        $document = [pscustomobject]@{
            Platform       = 'macos'
            Preset         = 'Core'
            NetworkMode    = 'Direct'
            Results        = @([pscustomobject]@{
                    Status      = 'Preview'
                    Number      = '03'
                    Id          = 'sources'
                    DurationMs  = 12
                    Message     = 'source preview'
                    RerunCommand = ''
                })
            Rollback       = ''
            SourceRestore  = [pscustomobject]@{
                Attempted  = $true
                Status     = 'Succeeded'
                DurationMs = 3
                Message    = 'restored'
            }
            ContinueCommand = './install.ps1 -Preset Core -FromStep sources'
            Status          = 'Succeeded'
            ExitCode        = 0
        }
        $originalOut = [Console]::Out
        $writer = [System.IO.StringWriter]::new()
        try {
            [Console]::SetOut($writer)
            Write-InstallRunText -Document $document
            $text = $writer.ToString()
        }
        finally {
            [Console]::SetOut($originalOut)
            $writer.Dispose()
        }

        $text | Should -Match 'Stage 1: platform=macos preset=Core network=Direct'
        $text | Should -Match '\[Preview\] 03 sources \(12ms\)'
        $text | Should -Match '\[Succeeded\] source-restore \(3ms\)'
        $text | Should -Match 'Result: status=Succeeded exitCode=0'
    }
}
