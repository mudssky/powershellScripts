Set-StrictMode -Version Latest

BeforeAll {
    # 通过测试专用跳过开关加载脚本函数，避免 dot-source 时直接执行 docker compose。
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:StartScriptPath = Join-Path $script:RepoRoot 'config/network/tailscale/derp/start.ps1'
    $script:OriginalSkipFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_TAILSCALE_DERP_START_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_TAILSCALE_DERP_START_MAIN = '1'

    . $script:StartScriptPath
}

AfterAll {
    if ($null -eq $script:OriginalSkipFlag) {
        Remove-Item Env:\PWSH_TEST_SKIP_TAILSCALE_DERP_START_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_TAILSCALE_DERP_START_MAIN', $script:OriginalSkipFlag, 'Process')
    }
}

Describe 'Show-Usage' {
    It 'documents the supported compose actions' {
        $usage = Show-Usage

        $usage | Should -Match '\[up\|down\|restart\|logs\|ps\|pull\|build\|config\|help\]'
        $usage | Should -Match '\./start\.ps1'
        $usage | Should -Match 'docker compose'
    }
}

Describe 'Get-ComposeInvocationPlan' {
    It 'runs build with plain progress before detached up' {
        $plan = Get-ComposeInvocationPlan -Action 'up' -ExtraArgs @('--no-cache')

        $plan.Count | Should -Be 2
        $plan[0].ComposeArgs | Should -Be @('build', '--no-cache')
        $plan[0].Environment.BUILDKIT_PROGRESS | Should -Be 'plain'
        $plan[1].ComposeArgs | Should -Be @('up', '-d', '--no-build')
    }

    It 'build action keeps plain progress for easier diagnosis' {
        $plan = Get-ComposeInvocationPlan -Action 'build' -ExtraArgs @('--no-cache')

        $plan.Count | Should -Be 1
        $plan[0].ComposeArgs | Should -Be @('build', '--no-cache')
        $plan[0].Environment.BUILDKIT_PROGRESS | Should -Be 'plain'
    }

    It 'logs action stays attached to derper without build environment tweaks' {
        $plan = Get-ComposeInvocationPlan -Action 'logs' -ExtraArgs @('--tail', '100')

        $plan.Count | Should -Be 1
        $plan[0].ComposeArgs | Should -Be @('logs', '-f', 'derper', '--tail', '100')
        $plan[0].Environment.Count | Should -Be 0
    }
}

Describe 'Get-ComposeBaseArgs' {
    It 'includes compose file, project directory and env file when present' {
        $scriptDir = Join-Path $TestDrive 'derp-with-env'
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        $composeFile = Join-Path $scriptDir 'compose.yaml'
        $envFile = Join-Path $scriptDir '.env.local'

        Set-Content -Path $composeFile -Value 'services: {}'
        Set-Content -Path $envFile -Value 'DERP_PUBLIC_IP=203.0.113.10'

        $args = Get-ComposeBaseArgs -ComposeFile $composeFile -ProjectDirectory $scriptDir -EnvFile $envFile

        $args | Should -Contain 'compose'
        $args | Should -Contain $composeFile
        $args | Should -Contain '--project-directory'
        $args | Should -Contain $scriptDir
        $args | Should -Contain '--env-file'
        $args | Should -Contain $envFile
    }

    It 'omits env file arguments when .env.local is absent' {
        $scriptDir = Join-Path $TestDrive 'derp-without-env'
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        $composeFile = Join-Path $scriptDir 'compose.yaml'

        Set-Content -Path $composeFile -Value 'services: {}'

        $args = Get-ComposeBaseArgs -ComposeFile $composeFile -ProjectDirectory $scriptDir -EnvFile (Join-Path $scriptDir '.env.local')

        $args | Should -Not -Contain '--env-file'
    }
}

Describe 'Invoke-DockerCompose' {
    It 'returns a preview string in dry run mode' {
        $preview = Invoke-DockerCompose -ComposeArgs @('compose', '-f', '/tmp/demo.yaml', 'ps') -DryRun

        $preview | Should -Be 'docker compose -f /tmp/demo.yaml ps'
    }

    It 'shows scoped environment variables in dry run mode' {
        $preview = Invoke-DockerCompose `
            -ComposeArgs @('compose', '-f', '/tmp/demo.yaml', 'build') `
            -Environment @{ BUILDKIT_PROGRESS = 'plain' } `
            -DryRun

        $preview | Should -Be 'BUILDKIT_PROGRESS=plain docker compose -f /tmp/demo.yaml build'
    }
}
