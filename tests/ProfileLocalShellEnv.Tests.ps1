Set-StrictMode -Version Latest

BeforeAll {
    $script:ProfileRootDir = Join-Path $PSScriptRoot '..' 'profile'
    . (Join-Path $script:ProfileRootDir 'features/environment.ps1')
}

Describe 'Import-ProfileLocalShellEnvFile' {
    BeforeEach {
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("profile-local-env-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TempRoot | Out-Null
        $script:EnvFile = Join-Path $script:TempRoot 'env.local.sh'
        $script:DataRoot = Join-Path $script:TempRoot 'Data'
        New-Item -ItemType Directory -Path $script:DataRoot | Out-Null

        $script:TrackedNames = @(
            'XH_API_KEY',
            'HERMES_HOME',
            'CARGO_HOME',
            'SCCACHE_DIR',
            'RUSTC_WRAPPER',
            'RUSTUP_HOME'
        )
        $script:OriginalEnv = @{}
        foreach ($name in $script:TrackedNames) {
            $script:OriginalEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
    }

    AfterEach {
        foreach ($name in $script:TrackedNames) {
            $value = $script:OriginalEnv[$name]
            if ($null -eq $value) {
                Remove-Item "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item "Env:$name" -Value $value
            }
        }

        if (Test-Path -LiteralPath $script:TempRoot) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'imports export lines and ignores alias/comments' {
        $cargoHome = Join-Path $script:DataRoot 'cache/cargo'
        $sccacheDir = Join-Path $script:DataRoot 'cache/sccache'
        $hermesHome = Join-Path $script:DataRoot 'agents/hermes'

        @(
            '# comment'
            "export XH_API_KEY='sk-test'"
            "export CARGO_HOME=`"$cargoHome`""
            "export SCCACHE_DIR='$sccacheDir'"
            "export HERMES_HOME=$hermesHome"
            'export RUSTC_WRAPPER=sccache'
            "alias skill-add-personal='echo hi'"
            'echo should-not-run'
        ) | Set-Content -LiteralPath $script:EnvFile -Encoding utf8

        $count = Import-ProfileLocalShellEnvFile -Path $script:EnvFile

        $count | Should -Be 5
        $env:XH_API_KEY | Should -Be 'sk-test'
        $env:CARGO_HOME | Should -Be $cargoHome
        $env:SCCACHE_DIR | Should -Be $sccacheDir
        $env:HERMES_HOME | Should -Be $hermesHome
        $env:RUSTC_WRAPPER | Should -Be 'sccache'
    }

    It 'skips path-sensitive vars when no ancestor path is reachable' {
        @(
            'export CARGO_HOME=/definitely/missing/volume/cache/cargo'
            'export RUSTC_WRAPPER=sccache'
        ) | Set-Content -LiteralPath $script:EnvFile -Encoding utf8

        $count = Import-ProfileLocalShellEnvFile -Path $script:EnvFile

        $count | Should -Be 1
        $env:RUSTC_WRAPPER | Should -Be 'sccache'
        $env:CARGO_HOME | Should -BeNullOrEmpty
    }

    It 'imports path-sensitive vars when a non-root ancestor exists' {
        $missingLeaf = Join-Path $script:DataRoot 'cache/not-created-yet/cargo'

        @(
            "export CARGO_HOME=`"$missingLeaf`""
            'export RUSTC_WRAPPER=sccache'
        ) | Set-Content -LiteralPath $script:EnvFile -Encoding utf8

        $count = Import-ProfileLocalShellEnvFile -Path $script:EnvFile

        $count | Should -Be 2
        $env:CARGO_HOME | Should -Be $missingLeaf
        $env:RUSTC_WRAPPER | Should -Be 'sccache'
    }
}
