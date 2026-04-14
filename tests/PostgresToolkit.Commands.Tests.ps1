Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $env:PWSH_TEST_SKIP_POSTGRES_TOOLKIT_MAIN = '1'

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
            'scripts/pwsh/devops/postgresql/commands/install-tools.ps1'
            'scripts/pwsh/devops/postgresql/platforms/windows.ps1'
            'scripts/pwsh/devops/postgresql/platforms/macos.ps1'
            'scripts/pwsh/devops/postgresql/platforms/linux.ps1'
            'scripts/pwsh/devops/postgresql/main.ps1'
        )) {
        . (Join-Path $script:RepoRoot $relativePath)
    }
}

Describe 'Get-PostgresToolkitHelpText' {
    It '输出四个核心命令和示例' {
        $helpText = Get-PostgresToolkitHelpText

        $helpText | Should -Match 'backup'
        $helpText | Should -Match 'restore'
        $helpText | Should -Match 'import-csv'
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
