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
