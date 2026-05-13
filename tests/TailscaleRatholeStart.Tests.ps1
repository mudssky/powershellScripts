Set-StrictMode -Version Latest

BeforeAll {
    # 通过测试专用跳过开关加载脚本函数，避免 dot-source 时直接执行 PM2。
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:StartScriptPath = Join-Path $script:RepoRoot 'config/network/rathole/start.ps1'
    $script:OriginalSkipFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_RATHOLE_START_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_RATHOLE_START_MAIN = '1'

    . $script:StartScriptPath
}

AfterAll {
    if ($null -eq $script:OriginalSkipFlag) {
        Remove-Item Env:\PWSH_TEST_SKIP_RATHOLE_START_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_RATHOLE_START_MAIN', $script:OriginalSkipFlag, 'Process')
    }
}

Describe 'Show-Usage' {
    It 'documents the supported PM2 actions and role switch' {
        $usage = Show-Usage

        $usage | Should -Match '\[start\|stop\|restart\|logs\|status\|delete\|save\|config\|help\]'
        $usage | Should -Match '-Role client\|server'
        $usage | Should -Match 'pm2 start'
    }
}

Describe 'Get-RatholeRoleConfig' {
    It 'defaults role metadata to the client files' {
        $config = Get-RatholeRoleConfig -Role 'client'

        $config.AppName | Should -Be 'rathole-client'
        $config.EcosystemPath | Should -Match 'rathole-client\.pm2\.config\.cjs$'
        $config.LocalConfigPath | Should -Match 'client\.local\.toml$'
        $config.ExamplePath | Should -Match 'client\.example\.toml$'
    }

    It 'resolves server files separately from client files' {
        $config = Get-RatholeRoleConfig -Role 'server'

        $config.AppName | Should -Be 'rathole-server'
        $config.EcosystemPath | Should -Match 'rathole-server\.pm2\.config\.cjs$'
        $config.LocalConfigPath | Should -Match 'server\.local\.toml$'
        $config.ExamplePath | Should -Match 'server\.example\.toml$'
    }
}

Describe 'Get-Pm2InvocationPlan' {
    It 'starts the selected role ecosystem file' {
        $roleConfig = Get-RatholeRoleConfig -Role 'client'

        $plan = Get-Pm2InvocationPlan -Action 'start' -RoleConfig $roleConfig -ExtraArgs @('--update-env')

        $plan.Count | Should -Be 1
        $plan[0].Pm2Args[0] | Should -Be 'start'
        $plan[0].Pm2Args[1] | Should -Be $roleConfig.EcosystemPath
        $plan[0].Pm2Args | Should -Contain '--update-env'
    }

    It 'routes restart to the selected PM2 app name' {
        $roleConfig = Get-RatholeRoleConfig -Role 'server'

        $plan = Get-Pm2InvocationPlan -Action 'restart' -RoleConfig $roleConfig -ExtraArgs @()

        $plan.Count | Should -Be 1
        $plan[0].Pm2Args | Should -Be @('restart', 'rathole-server')
    }

    It 'does not require a role-specific app name for save' {
        $roleConfig = Get-RatholeRoleConfig -Role 'client'

        $plan = Get-Pm2InvocationPlan -Action 'save' -RoleConfig $roleConfig -ExtraArgs @()

        $plan.Count | Should -Be 1
        $plan[0].Pm2Args | Should -Be @('save')
    }
}

Describe 'Invoke-Pm2Command' {
    It 'returns a preview string in dry run mode' {
        $preview = Invoke-Pm2Command -Pm2Args @('logs', 'rathole-client', '--lines', '100') -DryRun

        $preview | Should -Be 'pm2 logs rathole-client --lines 100'
    }
}

Describe 'Show-RatholeConfig' {
    It 'returns copy and start hints for the selected role' {
        $roleConfig = Get-RatholeRoleConfig -Role 'server'

        $config = Show-RatholeConfig -RoleConfig $roleConfig

        $config.Role | Should -Be 'server'
        $config.AppName | Should -Be 'rathole-server'
        $config.RecommendedCopyCommand | Should -Match 'server\.example\.toml'
        $config.RecommendedCopyCommand | Should -Match 'server\.local\.toml'
        $config.RecommendedStartCommand | Should -Be './start.ps1 start -Role server'
    }
}
