Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:InstallerPath = Join-Path $script:RepoRoot 'ai/skills/Install-Skills.ps1'
    $script:OriginalSkipMainFlag = [Environment]::GetEnvironmentVariable('SKILLS_INSTALLER_SKIP_MAIN', 'Process')
    $env:SKILLS_INSTALLER_SKIP_MAIN = '1'
    . $script:InstallerPath
}

AfterAll {
    if ($null -eq $script:OriginalSkipMainFlag) {
        Remove-Item Env:\SKILLS_INSTALLER_SKIP_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('SKILLS_INSTALLER_SKIP_MAIN', $script:OriginalSkipMainFlag, 'Process')
    }
}

Describe 'Skills 安装配置解析' {
    It '通过共享 JSON 配置生成默认远程 skill 安装计划' {
        $configPath = Join-Path $TestDrive 'skills.config.json'
        Set-Content -LiteralPath $configPath -Encoding utf8NoBOM -Value @'
{
  "version": 1,
  "scope": "global",
  "agents": ["claude", "codex"],
  "skills": {
    "agent-browser": {
      "description": "浏览器自动化",
      "source": "vercel-labs/agent-browser",
      "sourceType": "github",
      "skillPath": "skills/agent-browser/SKILL.md"
    }
  }
}
'@

        $config = Read-SkillsInstallerConfig -ConfigPath $configPath
        $plan = New-SkillsPlanFromConfig -Config $config

        $plan.Skills | Should -HaveCount 1
        $plan.Skills[0].Name | Should -Be 'agent-browser'
        $plan.Skills[0].Agents | Should -Be @('claude-code', 'codex')
        $plan.Skills[0].Scope | Should -Be 'global'
        $plan.Skills[0].Arguments | Should -Be @(
            'skills',
            'add',
            'vercel-labs/agent-browser',
            '--global',
            '--skill',
            'agent-browser',
            '--agent',
            'claude-code',
            'codex',
            '--yes'
        )
    }

    It 'CLI Agent 参数会覆盖配置中的默认 agent' {
        $configPath = Join-Path $TestDrive 'skills.config.json'
        Set-Content -LiteralPath $configPath -Encoding utf8NoBOM -Value @'
{
  "version": 1,
  "agents": ["claude"],
  "skills": {
    "supabase-postgres-best-practices": {
      "source": "supabase/agent-skills"
    }
  }
}
'@

        $config = Read-SkillsInstallerConfig -ConfigPath $configPath -CliParameters @{ Agent = @('codex', 'opencode') }
        $plan = New-SkillsPlanFromConfig -Config $config -OverrideAgents @('codex', 'opencode')

        $plan.Skills[0].Agents | Should -Be @('codex', 'opencode')
    }

    It 'project scope 未配置 projectPath 时默认使用仓库根目录' {
        $configPath = Join-Path $TestDrive 'skills.config.json'
        Set-Content -LiteralPath $configPath -Encoding utf8NoBOM -Value @'
{
  "version": 1,
  "scope": "project",
  "skills": {
    "agent-browser": {
      "source": "vercel-labs/agent-browser"
    }
  }
}
'@

        $config = Read-SkillsInstallerConfig -ConfigPath $configPath
        $plan = New-SkillsPlanFromConfig -Config $config

        $plan.Skills[0].Scope | Should -Be 'project'
        $plan.Skills[0].ProjectPath | Should -Be ([System.IO.Path]::GetFullPath($script:RepoRoot))
        $plan.Skills[0].Arguments | Should -Not -Contain '--global'
    }

    It 'IncludeDevAll 会发现 dev 目录下包含 SKILL.md 的本地 skill' {
        $configPath = Join-Path $TestDrive 'skills.config.json'
        $devRoot = Join-Path (Split-Path -Parent $configPath) 'dev'
        $localSkill = Join-Path $devRoot 'my-local-skill'
        New-Item -ItemType Directory -Path $localSkill -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $localSkill 'SKILL.md') -Encoding utf8NoBOM -Value @'
---
name: my-local-skill
description: 本地测试 skill。
---
'@
        Set-Content -LiteralPath $configPath -Encoding utf8NoBOM -Value @'
{
  "version": 1,
  "skills": {}
}
'@

        $oldRoot = $script:SkillsInstallerRoot
        try {
            $script:SkillsInstallerRoot = Split-Path -Parent $configPath
            $config = Read-SkillsInstallerConfig -ConfigPath $configPath
            $plan = New-SkillsPlanFromConfig -Config $config -IncludeDevAll
        }
        finally {
            $script:SkillsInstallerRoot = $oldRoot
        }

        $plan.Skills | Should -HaveCount 1
        $plan.Skills[0].Name | Should -Be 'my-local-skill'
        $plan.Skills[0].Source | Should -Be $localSkill
        $plan.Skills[0].SkillSelectors | Should -HaveCount 0
    }
}

Describe 'Skills 安装计划执行' {
    It 'tool setup 支持 check 命中后跳过 setup' {
        $tool = [pscustomobject]@{
            Type             = 'Tool'
            Name             = 'ctx7'
            Command          = 'npx'
            Arguments        = @('ctx7@latest', 'setup')
            WorkingDirectory = $TestDrive
            Check            = @{
                command  = 'npx'
                args     = @('ctx7@latest', 'skills', 'list', '--claude')
                contains = 'context7'
            }
        }
        $calls = New-Object 'System.Collections.Generic.List[object]'
        $runner = {
            param($Command, $Arguments, $WorkingDirectory, $LogPath, $AllowFailure)
            $calls.Add([pscustomobject]@{
                    Command      = $Command
                    Arguments    = $Arguments
                    AllowFailure = $AllowFailure
                }) | Out-Null
            return [pscustomobject]@{
                ExitCode = 0
                StdOut   = 'context7'
                StdErr   = ''
            }
        }

        Invoke-SkillsToolStep -Tool $tool -LogPath '' -CommandRunner $runner

        $calls | Should -HaveCount 1
        $calls[0].AllowFailure | Should -BeTrue
    }

    It 'skills CLI 安装项不生成 check 步骤' {
        $configPath = Join-Path $TestDrive 'skills.config.json'
        Set-Content -LiteralPath $configPath -Encoding utf8NoBOM -Value @'
{
  "version": 1,
  "skills": {
    "agent-browser": {
      "source": "vercel-labs/agent-browser"
    }
  }
}
'@

        $config = Read-SkillsInstallerConfig -ConfigPath $configPath
        $plan = New-SkillsPlanFromConfig -Config $config

        $plan.Steps | Should -HaveCount 1
        $plan.Steps[0].Type | Should -Be 'Skill'
        $plan.Steps[0].PSObject.Properties.Name | Should -Not -Contain 'Check'
    }

    It 'DryRun 不执行外部命令' {
        $configPath = Join-Path $TestDrive 'skills.config.json'
        Set-Content -LiteralPath $configPath -Encoding utf8NoBOM -Value @'
{
  "version": 1,
  "skills": {
    "agent-browser": {
      "source": "vercel-labs/agent-browser"
    }
  }
}
'@
        $runner = {
            throw 'DryRun 不应执行命令'
        }

        $exitCode = Invoke-SkillsInstallMain -ConfigPath $configPath -DryRun -CommandRunner $runner

        $exitCode | Should -Be 0
    }

    It 'WhatIf 不执行 skills add 命令' {
        $skill = [pscustomobject]@{
            Type             = 'Skill'
            Name             = 'agent-browser'
            Arguments        = @('skills', 'add', 'vercel-labs/agent-browser', '--yes')
            WorkingDirectory = $TestDrive
        }
        $runner = {
            throw 'WhatIf 不应执行命令'
        }

        Invoke-SkillsInstallStep -Skill $skill -LogPath '' -CommandRunner $runner -WhatIf
    }

    It 'WhatIf 不执行 tool check 或 setup 命令' {
        $tool = [pscustomobject]@{
            Type             = 'Tool'
            Name             = 'ctx7'
            Command          = 'npx'
            Arguments        = @('ctx7@latest', 'setup')
            WorkingDirectory = $TestDrive
            Check            = @{
                command  = 'npx'
                args     = @('ctx7@latest', 'skills', 'list', '--claude')
                contains = 'context7'
            }
        }
        $runner = {
            throw 'WhatIf 不应执行 tool check 或 setup'
        }

        Invoke-SkillsToolStep -Tool $tool -LogPath '' -CommandRunner $runner -WhatIf
    }

    It '附带命令按 pre/install/post 顺序进入执行计划' {
        $configPath = Join-Path $TestDrive 'skills.config.json'
        Set-Content -LiteralPath $configPath -Encoding utf8NoBOM -Value @'
{
  "version": 1,
  "skills": {
    "playwright-skill": {
      "source": "example/playwright-skill",
      "commands": [
        {
          "name": "prepare",
          "phase": "preInstall",
          "command": "pwsh",
          "args": ["-NoProfile"]
        },
        {
          "name": "install-browsers",
          "command": "npx",
          "args": ["playwright", "install"]
        }
      ]
    }
  }
}
'@

        $config = Read-SkillsInstallerConfig -ConfigPath $configPath
        $plan = New-SkillsPlanFromConfig -Config $config

        $plan.Steps.Type | Should -Be @('Command', 'Skill', 'Command')
        $plan.Steps[0].Name | Should -Be 'prepare'
        $plan.Steps[2].Name | Should -Be 'install-browsers'
    }
}
