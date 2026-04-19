Set-StrictMode -Version Latest

Describe 'Sync-ClaudeConfig' {
    BeforeAll {
        $script:WriteTestJson = {
            param(
                [Parameter(Mandatory)]
                [string]$Path,
                [Parameter(Mandatory)]
                [AllowNull()]
                $Value
            )

            $parentPath = Split-Path -Parent $Path
            if (-not (Test-Path -LiteralPath $parentPath)) {
                New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
            }

            $Value | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding utf8NoBOM
        }
    }

    BeforeEach {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Sync-ClaudeConfig.Tests.{0}" -f [System.Guid]::NewGuid())
        $script:SourceRoot = Join-Path $script:TempRoot 'source'
        $script:GlobalClaudePath = Join-Path $script:TempRoot 'home/.claude'
        $script:BackupRoot = Join-Path $script:TempRoot 'backups'
        $script:SyncScriptPath = Join-Path $script:ProjectRoot 'ai/coding/claude/Sync-ClaudeConfig.ps1'

        New-Item -ItemType Directory -Path (Join-Path $script:SourceRoot 'config') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:SourceRoot '.claude/output-styles') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:SourceRoot '.claude/commands') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:SourceRoot '.claude/ccline/themes') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:SourceRoot '.claude/skills/find-skills') -Force | Out-Null

        Set-Content -Path (Join-Path $script:SourceRoot '.claude/CLAUDE.md') -Value '# Shared Claude' -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:SourceRoot '.claude/config.json') -Value '{"shared":true}' -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:SourceRoot '.claude/output-styles/engineer-professional.md') -Value 'style' -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:SourceRoot '.claude/commands/commit.md') -Value 'commit' -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:SourceRoot '.claude/ccline/config.toml') -Value 'theme = "default"' -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:SourceRoot '.claude/ccline/models.toml') -Value 'model = "opus"' -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:SourceRoot '.claude/ccline/themes/default.toml') -Value 'name = "default"' -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:SourceRoot '.claude/skills/find-skills/SKILL.md') -Value '# Skill' -Encoding utf8NoBOM
    }

    AfterEach {
        if ($script:TempRoot -and (Test-Path -LiteralPath $script:TempRoot)) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
        }
    }

    It 'merges shared settings, local overrides and managed assets' {
        & $script:WriteTestJson -Path (Join-Path $script:SourceRoot 'config/settings.json') -Value @{
            '$schema'       = 'https://json.schemastore.org/claude-code-settings.json'
            env             = @{
                API_TIMEOUT_MS     = '3000'
                DISABLE_TELEMETRY  = '1'
                MCP_TIMEOUT        = '60000'
            }
            permissions     = @{
                allow       = @('Read', 'Edit')
                defaultMode = 'acceptEdits'
            }
            enabledPlugins  = @{
                'feature-dev@claude-plugins-official' = $false
                'compound-engineering@compound-engineering-plugin' = $true
            }
            statusLine      = @{
                type    = 'command'
                command = 'ccline'
            }
            model           = 'opus[1m]'
        }

        & $script:WriteTestJson -Path (Join-Path $script:SourceRoot 'config/settings.local.json') -Value @{
            env            = @{
                ANTHROPIC_API_KEY  = 'sk-local'
                ANTHROPIC_BASE_URL = 'http://127.0.0.1:3456'
            }
            permissions    = @{
                allow = @('Edit', 'Bash')
            }
            enabledPlugins = @{
                'feature-dev@claude-plugins-official' = $true
            }
        }

        $result = & $script:SyncScriptPath -SourceRoot $script:SourceRoot -GlobalClaudePath $script:GlobalClaudePath -BackupRoot $script:BackupRoot

        $result.HasLocalSettings | Should -BeTrue
        $result.ManagedFileCount | Should -BeGreaterThan 0

        $generatedSettings = Get-Content -Path (Join-Path $script:GlobalClaudePath 'settings.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 20
        $generatedSettings.env.API_TIMEOUT_MS | Should -Be '3000'
        $generatedSettings.env.DISABLE_TELEMETRY | Should -Be '1'
        $generatedSettings.env.ANTHROPIC_API_KEY | Should -Be 'sk-local'
        $generatedSettings.env.ANTHROPIC_BASE_URL | Should -Be 'http://127.0.0.1:3456'
        @($generatedSettings.permissions.allow) | Should -Be @('Read', 'Edit', 'Bash')
        $generatedSettings.enabledPlugins['feature-dev@claude-plugins-official'] | Should -BeTrue
        $generatedSettings.enabledPlugins['compound-engineering@compound-engineering-plugin'] | Should -BeTrue

        Test-Path -LiteralPath (Join-Path $script:GlobalClaudePath 'output-styles/engineer-professional.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:GlobalClaudePath 'skills/find-skills/SKILL.md') | Should -BeTrue
    }

    It 'allows shared template generation when settings.local.json is absent' {
        & $script:WriteTestJson -Path (Join-Path $script:SourceRoot 'config/settings.json') -Value @{
            env         = @{
                API_TIMEOUT_MS = '3000'
            }
            permissions = @{
                allow = @('Read')
            }
        }

        $result = & $script:SyncScriptPath -SourceRoot $script:SourceRoot -GlobalClaudePath $script:GlobalClaudePath -BackupRoot $script:BackupRoot

        $result.HasLocalSettings | Should -BeFalse
        $generatedSettings = Get-Content -Path (Join-Path $script:GlobalClaudePath 'settings.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 20
        $generatedSettings.env.Contains('ANTHROPIC_API_KEY') | Should -BeFalse
        @($generatedSettings.permissions.allow) | Should -Be @('Read')
    }

    It 'fails before writing when settings.local.json is invalid JSON' {
        & $script:WriteTestJson -Path (Join-Path $script:SourceRoot 'config/settings.json') -Value @{
            env = @{
                API_TIMEOUT_MS = '3000'
            }
        }

        New-Item -ItemType Directory -Path $script:GlobalClaudePath -Force | Out-Null
        Set-Content -Path (Join-Path $script:GlobalClaudePath 'settings.json') -Value '{"existing":true}' -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:SourceRoot 'config/settings.local.json') -Value '{ invalid json' -Encoding utf8NoBOM

        { & $script:SyncScriptPath -SourceRoot $script:SourceRoot -GlobalClaudePath $script:GlobalClaudePath -BackupRoot $script:BackupRoot } | Should -Throw

        $generatedSettings = Get-Content -Path (Join-Path $script:GlobalClaudePath 'settings.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 10
        $generatedSettings.existing | Should -BeTrue
    }

    It 'blocks shared template secrets and local-only env keys' {
        & $script:WriteTestJson -Path (Join-Path $script:SourceRoot 'config/settings.json') -Value @{
            env = @{
                ANTHROPIC_API_KEY = 'sk-should-not-ship'
            }
        }

        { & $script:SyncScriptPath -SourceRoot $script:SourceRoot -GlobalClaudePath $script:GlobalClaudePath -BackupRoot $script:BackupRoot } | Should -Throw
        Test-Path -LiteralPath (Join-Path $script:GlobalClaudePath 'settings.json') | Should -BeFalse
    }

    It 'migrates legacy symlink directories into a real ~/.claude directory while preserving runtime files' {
        if ($IsWindows) {
            Set-ItResult -Skipped -Because '此测试依赖稳定的目录符号链接行为，Windows 主机权限差异较大。'
            return
        }

        & $script:WriteTestJson -Path (Join-Path $script:SourceRoot 'config/settings.json') -Value @{
            env = @{
                API_TIMEOUT_MS = '3000'
            }
        }

        New-Item -ItemType Directory -Path (Split-Path -Parent $script:GlobalClaudePath) -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path $script:GlobalClaudePath -Target (Join-Path $script:SourceRoot '.claude') | Out-Null
        Set-Content -Path (Join-Path $script:GlobalClaudePath 'history.jsonl') -Value 'runtime-history' -Encoding utf8NoBOM

        $result = & $script:SyncScriptPath -SourceRoot $script:SourceRoot -GlobalClaudePath $script:GlobalClaudePath -BackupRoot $script:BackupRoot

        $targetItem = Get-Item -LiteralPath $script:GlobalClaudePath -Force
        $targetItem.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) | Should -BeFalse
        $result.MigratedFromLink | Should -BeTrue
        Test-Path -LiteralPath $result.BackupPath | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:GlobalClaudePath 'history.jsonl') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:GlobalClaudePath 'settings.json') | Should -BeTrue
    }

    It 'migrates legacy symlink directories even when runtime data contains broken symbolic links' {
        & $script:WriteTestJson -Path (Join-Path $script:SourceRoot 'config/settings.json') -Value @{
            env = @{
                API_TIMEOUT_MS = '3000'
            }
        }

        $legacyManagedRoot = Join-Path $script:SourceRoot '.claude'
        $brokenLinkPath = Join-Path $legacyManagedRoot 'debug/latest'
        $missingDebugFile = Join-Path $legacyManagedRoot 'debug/missing-session.txt'

        New-Item -ItemType Directory -Path (Join-Path $legacyManagedRoot 'debug') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $script:GlobalClaudePath) -Force | Out-Null

        try {
            # 这里故意创建一个失效符号链接，用来复现用户目录里已有运行态快捷入口时的迁移问题。
            New-Item -ItemType SymbolicLink -Path $brokenLinkPath -Target $missingDebugFile | Out-Null
            New-Item -ItemType SymbolicLink -Path $script:GlobalClaudePath -Target $legacyManagedRoot | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because "当前环境无法稳定创建符号链接：$($_.Exception.Message)"
            return
        }

        Set-Content -Path (Join-Path $script:GlobalClaudePath 'history.jsonl') -Value 'runtime-history' -Encoding utf8NoBOM

        { & $script:SyncScriptPath -SourceRoot $script:SourceRoot -GlobalClaudePath $script:GlobalClaudePath -BackupRoot $script:BackupRoot } | Should -Not -Throw

        $targetItem = Get-Item -LiteralPath $script:GlobalClaudePath -Force
        $targetItem.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:GlobalClaudePath 'history.jsonl') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:GlobalClaudePath 'settings.json') | Should -BeTrue
    }

    It 'removes stale managed files without deleting unmanaged files in the same directory' {
        & $script:WriteTestJson -Path (Join-Path $script:SourceRoot 'config/settings.json') -Value @{
            env = @{
                API_TIMEOUT_MS = '3000'
            }
        }

        Set-Content -Path (Join-Path $script:SourceRoot '.claude/output-styles/stale.md') -Value 'old-style' -Encoding utf8NoBOM
        & $script:SyncScriptPath -SourceRoot $script:SourceRoot -GlobalClaudePath $script:GlobalClaudePath -BackupRoot $script:BackupRoot *> $null

        Set-Content -Path (Join-Path $script:GlobalClaudePath 'output-styles/local-note.txt') -Value 'keep me' -Encoding utf8NoBOM
        Remove-Item -LiteralPath (Join-Path $script:SourceRoot '.claude/output-styles/stale.md') -Force

        & $script:SyncScriptPath -SourceRoot $script:SourceRoot -GlobalClaudePath $script:GlobalClaudePath -BackupRoot $script:BackupRoot *> $null

        Test-Path -LiteralPath (Join-Path $script:GlobalClaudePath 'output-styles/stale.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:GlobalClaudePath 'output-styles/local-note.txt') | Should -BeTrue
    }
}
