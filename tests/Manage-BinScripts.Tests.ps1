Set-StrictMode -Version Latest

Describe 'Manage-BinScripts' {
    BeforeEach {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Manage-BinScripts.Tests.{0}" -f [System.Guid]::NewGuid())
        $script:ManageScript = Join-Path $script:TempRoot 'Manage-BinScripts.ps1'

        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
        Copy-Item -Path (Join-Path $script:ProjectRoot 'Manage-BinScripts.ps1') -Destination $script:ManageScript -Force

        New-Item -ItemType Directory -Path (Join-Path $script:TempRoot 'scripts/pwsh/a') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:TempRoot 'scripts/pwsh/b') -Force | Out-Null

        Set-Content -Path (Join-Path $script:TempRoot 'scripts/pwsh/a/A.ps1') -Value "Write-Output 'A'" -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:TempRoot 'scripts/pwsh/b/B.ps1') -Value "Write-Output 'B'" -Encoding utf8NoBOM
    }

    AfterEach {
        if ($script:TempRoot -and (Test-Path -LiteralPath $script:TempRoot)) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
        }
    }

    It 'removes stale renamed shims and preserves unrelated shims during partial sync' {
        & $script:ManageScript -Action sync -Force

        $binDir = Join-Path $script:TempRoot 'bin'
        Test-Path -LiteralPath (Join-Path $binDir 'A.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $binDir 'B.ps1') | Should -BeTrue

        Rename-Item -LiteralPath (Join-Path $script:TempRoot 'scripts/pwsh/a/A.ps1') -NewName 'A2.ps1'

        & $script:ManageScript -Action sync -Force -Patterns @('scripts/pwsh/a/*.ps1')

        Test-Path -LiteralPath (Join-Path $binDir 'A.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $binDir 'A2.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $binDir 'B.ps1') | Should -BeTrue
    }
}
