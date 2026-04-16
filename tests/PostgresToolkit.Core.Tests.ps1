Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
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
    It '显式参数优先于 env-file 与进程环境变量' {
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

        $context = Resolve-PgContext -CliOptions @{
            host     = 'cli-host'
            database = 'cli-db'
            env_file = $envFile
        }

        $context.Host | Should -Be 'cli-host'
        $context.Port | Should -Be 5544
        $context.User | Should -Be 'env-file-user'
        $context.Password | Should -Be 'env-file-password'
        $context.Database | Should -Be 'cli-db'
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
