Set-StrictMode -Version Latest

Describe 'Build-PostgresToolkit.ps1' {
    It '生成单文件脚本和帮助文档，并且脚本可直接执行 help' {
        $outputScript = Join-Path $TestDrive 'Postgres-Toolkit.ps1'
        $outputHelp = Join-Path $TestDrive 'Postgres-Toolkit.Help.md'
        $sourceRoot = Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'devops' 'postgresql'
        $builderPath = Join-Path $sourceRoot 'build' 'Build-PostgresToolkit.ps1'

        & $builderPath -SourceRoot $sourceRoot -OutputScriptPath $outputScript -OutputHelpPath $outputHelp

        (Test-Path $outputScript) | Should -BeTrue
        (Test-Path $outputHelp) | Should -BeTrue
        (Get-Content -Path $outputScript -Raw) | Should -Match 'Invoke-PostgresToolkitCommand'
        (Get-Content -Path $outputHelp -Raw) | Should -Match 'import-csv'

        $helpOutput = @(& pwsh -NoProfile -File $outputScript help)
        $LASTEXITCODE | Should -Be 0
        ($helpOutput -join [Environment]::NewLine) | Should -Match 'install-tools'
    }
}
