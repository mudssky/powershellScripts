Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:RunnerRoot = Join-Path $script:RepoRoot 'scripts/pwsh/ai/agent-runner'

    foreach ($relativePath in @(
            'core/process.ps1'
            'agents/codex.ps1'
            'agents/claude.ps1'
            'agents/opencode.ps1'
        )) {
        . (Join-Path $script:RunnerRoot $relativePath)
    }
}

Describe 'AI agent command specs' {
    It 'builds codex exec args with model, reasoning effort, json and work dir' {
        $spec = New-CodexAgentCommandSpec -Prompt '修复测试' -Config @{
            model            = 'gpt-5.4'
            reasoning_effort = 'medium'
            work_dir         = '/repo'
            json             = $true
            extra_args       = @('--full-auto')
        }

        $spec.FilePath | Should -Be 'codex'
        $spec.WorkingDirectory | Should -Be '/repo'
        $spec.ArgumentList | Should -Be @(
            'exec',
            '--model', 'gpt-5.4',
            '-c', 'model_reasoning_effort="medium"',
            '--json',
            '--full-auto',
            '-C', '/repo',
            '修复测试'
        )
    }

    It 'builds claude print args and ignores reasoning effort' {
        $spec = New-ClaudeAgentCommandSpec -Prompt '总结变更' -Config @{
            model            = 'sonnet'
            reasoning_effort = 'high'
            work_dir         = '/repo'
            json             = $true
        }

        $spec.FilePath | Should -Be 'claude'
        $spec.WorkingDirectory | Should -Be '/repo'
        $spec.ArgumentList | Should -Be @(
            '-p', '总结变更',
            '--setting-sources', 'user,project,local',
            '--model', 'sonnet',
            '--output-format', 'json'
        )
        $spec.UnsupportedOptions | Should -Contain 'reasoning_effort'
    }

    It 'builds opencode run args with model and extra args' {
        $spec = New-OpenCodeAgentCommandSpec -Prompt '检查代码' -Config @{
            model      = 'openai/gpt-5.4'
            work_dir   = '/repo'
            extra_args = @('--agent', 'build')
        }

        $spec.FilePath | Should -Be 'opencode'
        $spec.WorkingDirectory | Should -Be '/repo'
        $spec.ArgumentList | Should -Be @(
            'run',
            '检查代码',
            '--model', 'openai/gpt-5.4',
            '--agent', 'build'
        )
    }

    It 'formats command previews without printing prompt text' {
        $spec = New-AiAgentCommandSpec -FilePath 'codex' -ArgumentList @('exec', 'secret prompt') -WorkingDirectory '/repo' -Prompt 'secret prompt'

        $preview = Format-AiAgentCommandPreview -Spec $spec

        $preview | Should -Match 'codex exec <PROMPT>'
        $preview | Should -Match 'PromptChars=13'
        $preview | Should -Not -Match 'secret prompt'
    }
}

Describe 'AI agent runner prompt and config' {
    BeforeAll {
        $script:OriginalAiAgentRunnerSkip = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_AI_AGENT_RUNNER_MAIN', 'Process')
        $env:PWSH_TEST_SKIP_AI_AGENT_RUNNER_MAIN = '1'

        foreach ($relativePath in @(
                'core/prompt.ps1'
                'core/config.ps1'
                'core/arguments.ps1'
                'main.ps1'
            )) {
            . (Join-Path $script:RunnerRoot $relativePath)
        }
    }

    AfterAll {
        if ($null -eq $script:OriginalAiAgentRunnerSkip) {
            Remove-Item Env:\PWSH_TEST_SKIP_AI_AGENT_RUNNER_MAIN -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_AI_AGENT_RUNNER_MAIN', $script:OriginalAiAgentRunnerSkip, 'Process')
        }
    }

    It 'loads the commit preset with medium reasoning effort' {
        $preset = Read-AiAgentPromptPreset -Name 'commit' -PromptsRoot (Join-Path $script:RunnerRoot 'prompts')

        $preset.Metadata.agent | Should -Be 'codex'
        $preset.Metadata.reasoning_effort | Should -Be 'medium'
        $preset.Content | Should -Match 'git commit'
        $preset.Content | Should -Match '不要执行 git push'
    }

    It 'loads the fix-tests preset with medium reasoning effort' {
        $preset = Read-AiAgentPromptPreset -Name 'fix-tests' -PromptsRoot (Join-Path $script:RunnerRoot 'prompts')

        $preset.Metadata.agent | Should -Be 'codex'
        $preset.Metadata.reasoning_effort | Should -Be 'medium'
        $preset.Content | Should -Match '测试'
        $preset.Content | Should -Match '不要执行 git push'
    }

    It 'lets CLI parameters override prompt frontmatter' {
        $preset = Read-AiAgentPromptPreset -Name 'commit' -PromptsRoot (Join-Path $script:RunnerRoot 'prompts')
        $config = Resolve-AiAgentExecutionConfig -Preset $preset -CliParameters @{
            Agent           = 'codex'
            ReasoningEffort = 'high'
            WorkDir         = '/repo'
        }

        $config.agent | Should -Be 'codex'
        $config.reasoning_effort | Should -Be 'high'
        $config.work_dir | Should -Be '/repo'
        $config.__content | Should -Match 'git commit'
    }

    It 'resolves run prompt text from direct prompt, prompt file and preset' {
        $promptFile = Join-Path $TestDrive 'task.md'
        Set-Content -Path $promptFile -Encoding utf8NoBOM -Value '解释当前仓库结构'

        (Resolve-AiAgentPromptText -Prompt '直接任务').Trim() | Should -Be '直接任务'
        (Resolve-AiAgentPromptText -PromptFile $promptFile).Trim() | Should -Be '解释当前仓库结构'
        (Resolve-AiAgentPromptText -PresetName 'commit' -PromptsRoot (Join-Path $script:RunnerRoot 'prompts')) | Should -Match 'git commit'
    }

    It 'appends structured requirements to direct prompt text' {
        $result = Resolve-AiAgentPromptText `
            -Prompt '检查当前变更' `
            -AppendPrompt @('只提交暂存区', '   ', '不要修改未暂存文件')

        $nl = [Environment]::NewLine
        $result | Should -Be "检查当前变更${nl}${nl}## 附加要求${nl}${nl}- 只提交暂存区${nl}- 不要修改未暂存文件"
    }

    It 'appends structured requirements to prompt files without changing source validation' {
        $promptFile = Join-Path $TestDrive 'task.md'
        Set-Content -Path $promptFile -Encoding utf8NoBOM -Value '修复当前失败测试'

        $result = Resolve-AiAgentPromptText -PromptFile $promptFile -AppendPrompt '不要修改文档'

        $result | Should -Match '修复当前失败测试'
        $result | Should -Match '## 附加要求'
        $result | Should -Match '- 不要修改文档'
        { Resolve-AiAgentPromptText -Prompt '直接任务' -PromptFile $promptFile -AppendPrompt '附加要求' } | Should -Throw '必须且只能提供一种 prompt 来源。'
    }

    It 'builds the commit shortcut as a commit preset request' {
        $request = ConvertTo-AiAgentRunRequest -CommandName 'commit' -Prompt $null -PromptFile $null -Preset $null

        $request.CommandName | Should -Be 'run'
        $request.Preset | Should -Be 'commit'
    }

    It 'builds the fix-tests shortcut as a fix-tests preset request' {
        $request = ConvertTo-AiAgentRunRequest -CommandName 'fix-tests' -Prompt $null -PromptFile $null -Preset $null

        $request.CommandName | Should -Be 'run'
        $request.Preset | Should -Be 'fix-tests'
    }
}

Describe 'AI agent runner public script' {
    It 'prints a safe dry-run preview for commit' {
        $scriptPath = Join-Path $script:RunnerRoot 'main.ps1'
        $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
        $output = & $pwshPath -NoProfile -File $scriptPath commit -DryRun -ReasoningEffort high 2>&1

        $LASTEXITCODE | Should -Be 0
        ($output -join "`n") | Should -Match 'codex exec'
        ($output -join "`n") | Should -Match 'model_reasoning_effort="high"'
        ($output -join "`n") | Should -Match '<PROMPT>'
        ($output -join "`n") | Should -Not -Match '检查当前 Git 变更'
    }

    It 'counts appended prompt text in dry-run without printing it' {
        $scriptPath = Join-Path $script:RunnerRoot 'main.ps1'
        $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source

        $baseOutput = & $pwshPath -NoProfile -File $scriptPath commit -DryRun 2>&1
        $appendOutput = & $pwshPath -NoProfile -File $scriptPath commit -DryRun -AppendPrompt '只提交暂存区' 2>&1

        $LASTEXITCODE | Should -Be 0
        $baseText = $baseOutput -join "`n"
        $appendText = $appendOutput -join "`n"
        $baseChars = [int]([regex]::Match($baseText, 'PromptChars=(\d+)').Groups[1].Value)
        $appendChars = [int]([regex]::Match($appendText, 'PromptChars=(\d+)').Groups[1].Value)

        $appendChars | Should -BeGreaterThan $baseChars
        $appendText | Should -Match '<PROMPT>'
        $appendText | Should -Not -Match '只提交暂存区'
    }
}
