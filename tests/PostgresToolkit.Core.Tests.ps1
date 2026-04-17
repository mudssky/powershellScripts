Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:ConfigSourceRoot = Join-Path $script:RepoRoot 'psutils' 'src' 'config'
    foreach ($relativePath in @(
            'convert.ps1'
            'discovery.ps1'
            'reader.ps1'
            'resolver.ps1'
        )) {
        . (Join-Path $script:ConfigSourceRoot $relativePath)
    }

    foreach ($relativePath in @(
            'scripts/pwsh/devops/postgresql/core/logging.ps1'
            'scripts/pwsh/devops/postgresql/core/process.ps1'
            'scripts/pwsh/devops/postgresql/core/arguments.ps1'
            'scripts/pwsh/devops/postgresql/core/connection.ps1'
            'scripts/pwsh/devops/postgresql/core/context.ps1'
            'scripts/pwsh/devops/postgresql/core/formats.ps1'
            'scripts/pwsh/devops/postgresql/core/validation.ps1'
        )) {
        . (Join-Path $script:RepoRoot $relativePath)
    }
}

Describe 'Resolve-PgContext' {
    BeforeEach {
        Remove-Item Env:\PGHOST -ErrorAction SilentlyContinue
        Remove-Item Env:\PGPORT -ErrorAction SilentlyContinue
        Remove-Item Env:\PGUSER -ErrorAction SilentlyContinue
        Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
        Remove-Item Env:\PGDATABASE -ErrorAction SilentlyContinue
    }

    It 'keeps explicit --env-file above process environment variables' {
        $envFile = Join-Path $TestDrive 'postgres.env'
        Set-Content -Path $envFile -Value @(
            'PGHOST=env-file-host'
            'PGPORT=5544'
            'PGUSER=env-file-user'
            'PGPASSWORD=env-file-password'
            'PGDATABASE=env-file-db'
        )

        $env:PGHOST = 'process-host'
        $env:PGPORT = '6432'
        $env:PGUSER = 'process-user'
        $env:PGPASSWORD = 'process-password'
        $env:PGDATABASE = 'process-db'

        $context = Resolve-PgContext -CliOptions @{ env_file = $envFile } -WorkingDirectory $TestDrive -ScriptDirectory $TestDrive

        $context.Host | Should -Be 'env-file-host'
        $context.Port | Should -Be 5544
        $context.User | Should -Be 'env-file-user'
        $context.Password | Should -Be 'env-file-password'
        $context.Database | Should -Be 'env-file-db'
    }

    It 'uses current working directory defaults before the script directory' {
        $workingDirectory = Join-Path $TestDrive 'cwd'
        $scriptDirectory = Join-Path $TestDrive 'script'
        New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $scriptDirectory -Force | Out-Null
        Set-Content -Path (Join-Path $workingDirectory '.env') -Value 'PGHOST=cwd-host'
        Set-Content -Path (Join-Path $scriptDirectory '.env') -Value 'PGHOST=script-host'

        $context = Resolve-PgContext -CliOptions @{} -WorkingDirectory $workingDirectory -ScriptDirectory $scriptDirectory

        $context.Host | Should -Be 'cwd-host'
    }

    It 'falls back to the script directory only when the working directory has no default env files' {
        $workingDirectory = Join-Path $TestDrive 'cwd-empty'
        $scriptDirectory = Join-Path $TestDrive 'script-fallback'
        New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $scriptDirectory -Force | Out-Null
        Set-Content -Path (Join-Path $scriptDirectory '.env') -Value @(
            'PGHOST=script-host'
            'PGDATABASE=script-db'
        )

        $context = Resolve-PgContext -CliOptions @{} -WorkingDirectory $workingDirectory -ScriptDirectory $scriptDirectory

        $context.Host | Should -Be 'script-host'
        $context.Database | Should -Be 'script-db'
    }

    It 'does not mix script-directory defaults into a partially populated working directory' {
        $workingDirectory = Join-Path $TestDrive 'cwd-partial'
        $scriptDirectory = Join-Path $TestDrive 'script-extra'
        New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $scriptDirectory -Force | Out-Null
        Set-Content -Path (Join-Path $workingDirectory '.env') -Value 'PGHOST=cwd-host'
        Set-Content -Path (Join-Path $scriptDirectory '.env.local') -Value 'PGUSER=script-user'

        $context = Resolve-PgContext -CliOptions @{} -WorkingDirectory $workingDirectory -ScriptDirectory $scriptDirectory

        $context.Host | Should -Be 'cwd-host'
        $context.User | Should -BeNullOrEmpty
    }

    It 'keeps process environment variables above auto-discovered env defaults' {
        $workingDirectory = Join-Path $TestDrive 'cwd-defaults'
        New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null
        Set-Content -Path (Join-Path $workingDirectory '.env') -Value @(
            'PGHOST=file-host'
            'PGUSER=file-user'
        )

        $env:PGHOST = 'process-host'
        $env:PGUSER = 'process-user'

        $context = Resolve-PgContext -CliOptions @{} -WorkingDirectory $workingDirectory -ScriptDirectory $workingDirectory

        $context.Host | Should -Be 'process-host'
        $context.User | Should -Be 'process-user'
    }

    It 'throws on invalid auto-discovered env lines' {
        $workingDirectory = Join-Path $TestDrive 'cwd-invalid'
        New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null
        Set-Content -Path (Join-Path $workingDirectory '.env') -Value @(
            'PGHOST=good'
            'not valid'
        )

        {
            Resolve-PgContext -CliOptions @{} -WorkingDirectory $workingDirectory -ScriptDirectory $workingDirectory
        } | Should -Throw '无效 env 行'
    }
}

Describe 'Resolve-PgRestoreInputKind' {
    It '识别 sql dump tar 和目录' {
        $sqlPath = Join-Path $TestDrive 'sample.sql'
        $dumpPath = Join-Path $TestDrive 'sample.dump'
        $tarPath = Join-Path $TestDrive 'sample.tar'
        $dirPath = Join-Path $TestDrive 'sample-dir'

        Set-Content -Path $sqlPath -Value '-- sql'
        Set-Content -Path $dumpPath -Value 'custom'
        Set-Content -Path $tarPath -Value 'tar'
        New-Item -Path $dirPath -ItemType Directory | Out-Null

        (Resolve-PgRestoreInputKind -InputPath $sqlPath) | Should -Be 'sql'
        (Resolve-PgRestoreInputKind -InputPath $dumpPath) | Should -Be 'archive'
        (Resolve-PgRestoreInputKind -InputPath $tarPath) | Should -Be 'archive'
        (Resolve-PgRestoreInputKind -InputPath $dirPath) | Should -Be 'directory'
    }
}

Describe 'ConvertFrom-LongOptionList' {
    It '解析 --flag value 与 --flag=value 形式' {
        $parsed = ConvertFrom-LongOptionList -Arguments @(
            '--host', 'db.local',
            '--database=app',
            '--header',
            '--jobs', '4'
        )

        $parsed.host | Should -Be 'db.local'
        $parsed.database | Should -Be 'app'
        $parsed.header | Should -BeTrue
        $parsed.jobs | Should -Be '4'
    }
}

Describe 'Invoke-PgNativeCommand' {
    It 'dry-run 只返回命令预览' {
        $spec = New-PgNativeCommandSpec -FilePath 'pg_dump' -ArgumentList @('-Fc', '-f', 'app.dump') -Environment @{
            PGPASSWORD = 'secret'
        }

        $result = Invoke-PgNativeCommand -Spec $spec -DryRun

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'pg_dump'
        $result.Output | Should -Match 'app.dump'
    }
}
