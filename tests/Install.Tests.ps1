Set-StrictMode -Version Latest

Describe 'install.ps1' {
    BeforeEach {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        # Linux 容器里的 /tmp 可能挂载为不可执行，mock 外部命令需放在工作区内。
        $script:TempRoot = Join-Path $script:ProjectRoot (".install-tests.{0}" -f [System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

        Copy-Item -Path (Join-Path $script:ProjectRoot 'install.ps1') -Destination (Join-Path $script:TempRoot 'install.ps1') -Force

        $orchestratorSource = Join-Path $script:ProjectRoot 'scripts/pwsh/install/InstallOrchestrator.psm1'
        $registrySource = Join-Path $script:ProjectRoot 'config/install/steps.psd1'
        if (Test-Path -LiteralPath $orchestratorSource -PathType Leaf) {
            $moduleTarget = Join-Path $script:TempRoot 'scripts/pwsh/install'
            New-Item -ItemType Directory -Path $moduleTarget -Force | Out-Null
            Copy-Item -LiteralPath $orchestratorSource -Destination (Join-Path $moduleTarget 'InstallOrchestrator.psm1') -Force
        }
        if (Test-Path -LiteralPath $registrySource -PathType Leaf) {
            $registryTarget = Join-Path $script:TempRoot 'config/install'
            New-Item -ItemType Directory -Path $registryTarget -Force | Out-Null
            Copy-Item -LiteralPath $registrySource -Destination (Join-Path $registryTarget 'steps.psd1') -Force
        }

        New-Item -ItemType Directory -Path (Join-Path $script:TempRoot 'scripts/bash') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:TempRoot 'bin') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:TempRoot 'mock-bin') -Force | Out-Null

        Set-Content -Path (Join-Path $script:TempRoot 'Manage-BinScripts.ps1') -Value @'
param([string]$Action, [switch]$Force)
"Action=$Action Force=$Force" | Set-Content -Path (Join-Path $PSScriptRoot 'manage-called.log') -Encoding utf8NoBOM
'@ -Encoding utf8NoBOM

        Set-Content -Path (Join-Path $script:TempRoot 'scripts/bash/build.sh') -Value @'
#!/usr/bin/env bash
printf "%s\n" "$*" >"$(cd "$(dirname "$0")/../.." && pwd)/bash-build-called.log"
'@ -Encoding utf8NoBOM

        Set-Content -Path (Join-Path $script:TempRoot 'mock-bin/bash') -Value @'
#!/bin/sh
printf "%s\n" "$*" >"${INSTALL_TEST_BASH_LOG}"
exit 0
'@ -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:TempRoot 'mock-bin/nbstripout') -Value "#!/bin/sh`nexit 0`n" -Encoding utf8NoBOM

        $legacyAppPaths = @(
            'profile/installer/installApp.ps1',
            'linux/04installApps.ps1'
        )
        foreach ($relativePath in $legacyAppPaths) {
            $appPath = Join-Path $script:TempRoot $relativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $appPath) -Force | Out-Null
            Set-Content -LiteralPath $appPath -Encoding utf8NoBOM -Value @'
"legacy-app" | Set-Content -LiteralPath (Join-Path $ProjectRoot 'legacy-app-called.log') -Encoding utf8NoBOM
'@
        }

        if ($IsMacOS) {
            $verifyPath = Join-Path $script:TempRoot 'macos/99verifyInstall.zsh'
            New-Item -ItemType Directory -Path (Split-Path -Parent $verifyPath) -Force | Out-Null
            Set-Content -LiteralPath $verifyPath -Encoding utf8NoBOM -Value "#!/usr/bin/env zsh`nprintf 'verify-leaf-noise\\n'`n"
        }
        else {
            $verifyRelativePath = if ($IsWindows) { 'windows/99verifyInstall.ps1' } else { 'linux/99verifyInstall.ps1' }
            $verifyPath = Join-Path $script:TempRoot $verifyRelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $verifyPath) -Force | Out-Null
            Set-Content -LiteralPath $verifyPath -Encoding utf8NoBOM -Value "Write-Output 'verify-leaf-noise'`n"
        }

        if (-not $IsWindows) {
            chmod +x (Join-Path $script:TempRoot 'mock-bin/bash')
            chmod +x (Join-Path $script:TempRoot 'mock-bin/nbstripout')
            chmod +x (Join-Path $script:TempRoot 'scripts/bash/build.sh')
        }

        $script:OriginalPath = $env:PATH
        $env:PATH = (Join-Path $script:TempRoot 'mock-bin') + [IO.Path]::PathSeparator + $env:PATH
    }

    AfterEach {
        $env:PATH = $script:OriginalPath
        if ($script:TempRoot -and (Test-Path -LiteralPath $script:TempRoot)) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
        }
    }

    It 'invokes scripts/bash/build.sh during default install flow' -Skip:$IsWindows {
        $bashLog = Join-Path $script:TempRoot 'bash-command.log'
        $env:INSTALL_TEST_BASH_LOG = $bashLog

        $result = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') 2>&1

        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:TempRoot 'manage-called.log') | Should -BeTrue
        Test-Path -LiteralPath $bashLog | Should -BeTrue
        (Get-Content -LiteralPath $bashLog -Raw) | Should -Match 'scripts[/\\]bash[/\\]build\.sh'
        ($result | Out-String) | Should -Match 'Bash'
    }

    It 'lists Stage 1 steps as one JSON document' {
        $output = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') -ListSteps -OutputFormat Json 2>$null

        $LASTEXITCODE | Should -Be 0
        $document = $output | Out-String | ConvertFrom-Json
        @($document.Steps.Id) | Should -Contain 'sources'
        @($document.Steps.Id) | Should -Contain 'verify'
    }

    It 'keeps installApp compatibility and prints a deprecation warning' {
        $result = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') -installApp 2>&1

        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:TempRoot 'legacy-app-called.log') | Should -BeTrue
        ($result | Out-String) | Should -Match '弃用'
        Test-Path -LiteralPath (Join-Path $script:TempRoot 'manage-called.log') | Should -BeFalse
    }

    It 'rejects step selection without a preset before legacy side effects' {
        $result = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') -Step sources 2>&1

        $LASTEXITCODE | Should -Be 2
        Test-Path -LiteralPath (Join-Path $script:TempRoot 'manage-called.log') | Should -BeFalse
        ($result | Out-String) | Should -Match 'Preset'
    }

    It 'rejects mutually exclusive step and interaction parameters' {
        $stepResult = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') `
            -Preset Core -Step sources -FromStep fonts 2>&1
        $stepExitCode = $LASTEXITCODE
        $interactionResult = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') `
            -Preset Core -Unattended -NonInteractive 2>&1
        $interactionExitCode = $LASTEXITCODE

        $stepExitCode | Should -Be 2
        $interactionExitCode | Should -Be 2
        ($stepResult | Out-String) | Should -Match '不能同时使用'
        ($interactionResult | Out-String) | Should -Match '不能同时使用'
        Test-Path -LiteralPath (Join-Path $script:TempRoot 'manage-called.log') | Should -BeFalse
    }

    It 'rejects ListSteps execution parameters and a standalone OutputFormat' {
        $listResult = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') `
            -ListSteps -Preset Core 2>&1
        $listExitCode = $LASTEXITCODE
        $formatOutput = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') `
            -OutputFormat Json 2>$null
        $formatExitCode = $LASTEXITCODE

        $listExitCode | Should -Be 2
        ($listResult | Out-String) | Should -Match 'ListSteps 只能'
        $formatExitCode | Should -Be 2
        ($formatOutput | Out-String | ConvertFrom-Json).Status | Should -Be 'InvalidArguments'
        Test-Path -LiteralPath (Join-Path $script:TempRoot 'manage-called.log') | Should -BeFalse
    }

    It 'rejects installApp mixed with the orchestrator' {
        $result = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') `
            -installApp -Preset Full 2>&1

        $LASTEXITCODE | Should -Be 2
        ($result | Out-String) | Should -Match 'installApp 不能'
        Test-Path -LiteralPath (Join-Path $script:TempRoot 'legacy-app-called.log') | Should -BeFalse
    }

    It 'returns one JSON argument error document' {
        $output = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') `
            -Step sources -OutputFormat Json 2>$null

        $LASTEXITCODE | Should -Be 2
        $document = $output | Out-String | ConvertFrom-Json
        $document.Status | Should -Be 'InvalidArguments'
        $document.ExitCode | Should -Be 2
    }

    It 'keeps leaf stdout inside one orchestrator JSON document' {
        $output = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') `
            -Preset Core -Step verify -OutputFormat Json 2>$null

        $LASTEXITCODE | Should -Be 0
        $document = $output | Out-String | ConvertFrom-Json
        $document.Status | Should -Be 'Succeeded'
        @($document.Results).Count | Should -Be 1
        $document.Results[0].Message | Should -Match 'verify-leaf-noise'
    }

    It 'returns one Blocked JSON document when future platform leaves are missing' {
        $output = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') -Preset Core -OutputFormat Json 2>$null

        $LASTEXITCODE | Should -Be 10
        Test-Path -LiteralPath (Join-Path $script:TempRoot 'manage-called.log') | Should -BeFalse
        $document = $output | Out-String | ConvertFrom-Json
        $document.Status | Should -Be 'Blocked'
        $document.ExitCode | Should -Be 10
        @($document.Results).Count | Should -Be 6
    }
}
