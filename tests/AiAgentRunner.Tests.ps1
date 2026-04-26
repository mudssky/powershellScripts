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

    It 'builds the commit shortcut as a commit preset request' {
        $request = ConvertTo-AiAgentRunRequest -CommandName 'commit' -Prompt $null -PromptFile $null -Preset $null

        $request.CommandName | Should -Be 'run'
        $request.Preset | Should -Be 'commit'
    }
}
