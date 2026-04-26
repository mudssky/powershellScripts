Set-StrictMode -Version Latest

Describe 'install.ps1' {
    BeforeEach {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Install.Tests.{0}" -f [System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

        Copy-Item -Path (Join-Path $script:ProjectRoot 'install.ps1') -Destination (Join-Path $script:TempRoot 'install.ps1') -Force

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

    It 'invokes scripts/bash/build.sh during default install flow' {
        $bashLog = Join-Path $script:TempRoot 'bash-command.log'
        $env:INSTALL_TEST_BASH_LOG = $bashLog

        $result = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') 2>&1

        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:TempRoot 'manage-called.log') | Should -BeTrue
        Test-Path -LiteralPath $bashLog | Should -BeTrue
        (Get-Content -LiteralPath $bashLog -Raw) | Should -Match 'scripts[/\\]bash[/\\]build\.sh'
        ($result | Out-String) | Should -Match 'Bash'
    }
}
