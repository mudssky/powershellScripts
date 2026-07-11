Describe 'Format-PowerShellCode archive 排除' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:FormatterSource = Join-Path $script:RepoRoot 'scripts/pwsh/devops/Format-PowerShellCode.ps1'
    }

    BeforeEach {
        $script:TestRepo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:FormatterTarget = Join-Path $script:TestRepo 'scripts/pwsh/devops/Format-PowerShellCode.ps1'
        $script:ActiveScript = Join-Path $script:TestRepo 'scripts/active.ps1'
        $script:ArchivedScript = Join-Path $script:TestRepo 'archive/legacy.ps1'

        New-Item -ItemType Directory -Path (Split-Path -Parent $script:FormatterTarget) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $script:ActiveScript) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $script:ArchivedScript) -Force | Out-Null
        Copy-Item -LiteralPath $script:FormatterSource -Destination $script:FormatterTarget
        Set-Content -LiteralPath $script:ActiveScript -Value 'Get-ChildItem'
        Set-Content -LiteralPath $script:ArchivedScript -Value 'Get-ChildItem'
    }

    It '递归模式跳过 archive 并保留活动脚本' {
        Push-Location $script:TestRepo
        try {
            $output = & pwsh -NoProfile -File $script:FormatterTarget -Path . -Recurse -ShowOnly 2>&1 | Out-String

            $LASTEXITCODE | Should -Be 0
            $output | Should -Match 'scripts[/\\]active\.ps1'
            $output | Should -Not -Match 'archive[/\\]legacy\.ps1'
        }
        finally {
            Pop-Location
        }
    }

    It 'Git changed 模式跳过 archive 并保留活动脚本' {
        if (-not (Get-Command -Name git -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because '当前测试环境未安装 Git'
            return
        }

        Push-Location $script:TestRepo
        try {
            & git init --quiet
            & git config user.email 'ci@example.com'
            & git config user.name 'ci'
            & git add .
            & git commit --quiet -m 'init'

            Set-Content -LiteralPath $script:ActiveScript -Value 'get-childitem -path .'
            Set-Content -LiteralPath $script:ArchivedScript -Value 'get-childitem -path .'

            $output = & pwsh -NoProfile -File $script:FormatterTarget -GitChanged -ShowOnly 2>&1 | Out-String

            $LASTEXITCODE | Should -Be 0
            $output | Should -Match 'scripts[/\\]active\.ps1'
            $output | Should -Not -Match 'archive[/\\]legacy\.ps1'
        }
        finally {
            Pop-Location
        }
    }
}
