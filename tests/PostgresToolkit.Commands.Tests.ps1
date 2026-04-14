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
