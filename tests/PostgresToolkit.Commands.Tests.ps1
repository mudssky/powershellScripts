Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:ConfigSourceRoot = Join-Path $script:RepoRoot 'psutils' 'src' 'config'
    $script:OriginalSkipToolkitMain = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_POSTGRES_TOOLKIT_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_POSTGRES_TOOLKIT_MAIN = '1'

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
            'scripts/pwsh/devops/postgresql/commands/help.ps1'
            'scripts/pwsh/devops/postgresql/commands/backup.ps1'
            'scripts/pwsh/devops/postgresql/commands/restore.ps1'
            'scripts/pwsh/devops/postgresql/commands/import-csv.ps1'
            'scripts/pwsh/devops/postgresql/commands/pgbackrest.ps1'
            'scripts/pwsh/devops/postgresql/commands/install-tools.ps1'
            'scripts/pwsh/devops/postgresql/platforms/windows.ps1'
            'scripts/pwsh/devops/postgresql/platforms/macos.ps1'
            'scripts/pwsh/devops/postgresql/platforms/linux.ps1'
            'scripts/pwsh/devops/postgresql/main.ps1'
        )) {
        . (Join-Path $script:RepoRoot $relativePath)
    }
}

AfterAll {
    if ($null -eq $script:OriginalSkipToolkitMain) {
        Remove-Item Env:\PWSH_TEST_SKIP_POSTGRES_TOOLKIT_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_POSTGRES_TOOLKIT_MAIN', $script:OriginalSkipToolkitMain, 'Process')
    }
}

Describe 'Get-PostgresToolkitHelpText' {
    It '输出四个核心命令和示例' {
        $helpText = Get-PostgresToolkitHelpText

        $helpText | Should -Match 'backup'
        $helpText | Should -Match 'restore'
        $helpText | Should -Match 'import-csv'
        $helpText | Should -Match 'pgbackrest'
        $helpText | Should -Match 'install-tools'
        $helpText | Should -Match 'Postgres-Toolkit.ps1 backup'
    }
}

Describe 'Invoke-PostgresToolkitCommand' {
    It '未传命令时返回帮助文本而不是抛错' {
        $result = Invoke-PostgresToolkitCommand -CommandName '' -RawArguments @()

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Usage'
    }

    It 'pgbackrest 不读取当前目录的通用 .env' {
        $workDir = Join-Path $TestDrive 'invalid-env-cwd'
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        Set-Content -Path (Join-Path $workDir '.env') -Value 'not valid'

        Push-Location $workDir
        try {
            $result = Invoke-PostgresToolkitCommand -CommandName 'pgbackrest' -RawArguments @(
                '--action', 'backup',
                '--type', 'incr',
                '--config', './pgbackrest.conf.local',
                '--dry-run'
            )
        }
        finally {
            Pop-Location
        }

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'pgbackrest'
        $result.Output | Should -Match '--type=incr'
    }
}

Describe 'New-PgBackupCommandSpec' {
    It '默认生成 custom 格式 pg_dump 命令' {
        $spec = New-PgBackupCommandSpec -CliOptions @{
            database = 'app'
            output   = './app.dump'
        } -Context ([PSCustomObject]@{
            Host     = '127.0.0.1'
            Port     = 5432
            User     = 'postgres'
            Password = 'secret'
            Database = 'app'
        })

        $spec.FilePath | Should -Be 'pg_dump'
        ($spec.ArgumentList -join ' ') | Should -Match '-Fc'
        ($spec.ArgumentList -join ' ') | Should -Match 'app.dump'
    }
}

Describe 'New-PgBackRestCommandSpec' {
    It '生成 pgBackRest 增量备份命令' {
        $spec = New-PgBackRestCommandSpec -CliOptions @{
            action        = 'backup'
            type          = 'incr'
            config        = './pgbackrest.conf.local'
            stanza        = 'lobechat'
            pg1_host      = 'macmini'
            pg1_host_type = 'ssh'
            pg1_host_user = 'postgres'
            pg1_path      = '/var/lib/postgresql/data'
            repo1_path    = '/backup/pgbackrest'
        }

        $spec.FilePath | Should -Be 'pgbackrest'
        $spec.ArgumentList | Should -Contain '--config=./pgbackrest.conf.local'
        $spec.ArgumentList | Should -Contain '--stanza=lobechat'
        $spec.ArgumentList | Should -Contain '--pg1-host=macmini'
        $spec.ArgumentList | Should -Contain '--pg1-host-type=ssh'
        $spec.ArgumentList | Should -Contain '--type=incr'
        $spec.ArgumentList[-1] | Should -Be 'backup'
    }

    It '从 env-file 读取 pgBackRest 默认值' {
        $envFile = Join-Path $TestDrive 'pgbackrest.env.local'
        Set-Content -Path $envFile -Value @(
            'PGBR_CONFIG=./pgbackrest.conf.local'
            'PGBR_STANZA=lobechat'
            'PGBR_PG1_HOST=macmini'
            'PGBR_PG1_HOST_TYPE=ssh'
            'PGBR_BACKUP_TYPE=diff'
        )

        $spec = New-PgBackRestCommandSpec -CliOptions @{
            env_file = $envFile
            action   = 'backup'
        }

        $spec.ArgumentList | Should -Contain '--config=./pgbackrest.conf.local'
        $spec.ArgumentList | Should -Contain '--stanza=lobechat'
        $spec.ArgumentList | Should -Contain '--pg1-host=macmini'
        $spec.ArgumentList | Should -Contain '--pg1-host-type=ssh'
        $spec.ArgumentList | Should -Contain '--type=diff'
    }

    It '拒绝把 pgBackRest action 透传成任意命令' {
        {
            New-PgBackRestCommandSpec -CliOptions @{
                action = 'restore'
            }
        } | Should -Throw '*pgbackrest --action 只支持*'
    }
}

Describe 'New-PgRestoreCommandSpec' {
    It 'sql 文件切换到 psql 恢复路径' {
        $inputPath = Join-Path $TestDrive 'sample.sql'
        Set-Content -Path $inputPath -Value '-- sql'

        $spec = New-PgRestoreCommandSpec -CliOptions @{
            input           = $inputPath
            target_database = 'restore_db'
        } -Context ([PSCustomObject]@{
            Host     = '127.0.0.1'
            Port     = 5432
            User     = 'postgres'
            Password = 'secret'
            Database = 'postgres'
        })

        $spec.FilePath | Should -Be 'psql'
        ($spec.ArgumentList -join ' ') | Should -Match 'restore_db'
        ($spec.ArgumentList -join ' ') | Should -Match '-f'
    }

    It 'archive 文件走 pg_restore 并支持 --clean' {
        $inputPath = Join-Path $TestDrive 'sample.dump'
        Set-Content -Path $inputPath -Value 'archive'

        $spec = New-PgRestoreCommandSpec -CliOptions @{
            input           = $inputPath
            target_database = 'restore_db'
            clean           = $true
        } -Context ([PSCustomObject]@{
            Host     = '127.0.0.1'
            Port     = 5432
            User     = 'postgres'
            Password = 'secret'
            Database = 'postgres'
        })

        $spec.FilePath | Should -Be 'pg_restore'
        $spec.ArgumentList | Should -Contain '--clean'
    }
}

Describe 'New-PgImportCsvCommandSpec' {
    It '生成带 header 的 \copy 语句' {
        $csvPath = Join-Path $TestDrive 'users.csv'
        Set-Content -Path $csvPath -Value "id,name`n1,Alice"

        $spec = New-PgImportCsvCommandSpec -CliOptions @{
            input  = $csvPath
            table  = 'users'
            header = $true
        } -Context ([PSCustomObject]@{
            Host     = '127.0.0.1'
            Port     = 5432
            User     = 'postgres'
            Password = 'secret'
            Database = 'app'
        })

        $spec.FilePath | Should -Be 'psql'
        ($spec.ArgumentList -join ' ') | Should -Match '\\copy public.users'
        ($spec.ArgumentList -join ' ') | Should -Match 'HEADER true'
    }
}

Describe 'Get-PgInstallPlan' {
    It 'Windows auto 策略优先返回 winget 命令' {
        $plan = Get-PgInstallPlan -Platform 'windows' -PackageManager 'auto' -Tools @('psql', 'pg_dump')

        $plan.PackageManager | Should -Be 'winget'
        $plan.Commands[0] | Should -Match 'winget'
    }

    It 'Linux apt 策略返回 apt install 命令' {
        $plan = Get-PgInstallPlan -Platform 'linux' -PackageManager 'apt' -Tools @('psql')

        $plan.Commands[0] | Should -Match 'apt-get install'
    }
}
