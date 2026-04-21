Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:StartContainerScriptPath = Join-Path $script:RepoRoot 'scripts/pwsh/devops/start-container.ps1'
    $script:OriginalSkipFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_START_CONTAINER_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_START_CONTAINER_MAIN = '1'

    . $script:StartContainerScriptPath
}

AfterAll {
    if ($null -eq $script:OriginalSkipFlag) {
        Remove-Item Env:\PWSH_TEST_SKIP_START_CONTAINER_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_START_CONTAINER_MAIN', $script:OriginalSkipFlag, 'Process')
    }
}

Describe 'New-LocalhostComposeOverrideFile' {
    It 'rewrites inline array ports to loopback mappings' {
        $composePath = Join-Path $TestDrive 'inline.compose.yml'
        Set-Content -Path $composePath -Value @'
services:
  redis:
    ports: ["6379:6379"]
'@

        $overridePath = New-LocalhostComposeOverrideFile -ComposePath $composePath -ServiceNames @('redis')
        $overrideContent = Get-Content -LiteralPath $overridePath -Raw

        $overrideContent | Should -Match '127\.0\.0\.1:6379:6379'
    }

    It 'rewrites multi-line tcp and udp ports and keeps protocol suffixes' {
        $composePath = Join-Path $TestDrive 'udp.compose.yml'
        Set-Content -Path $composePath -Value @'
services:
  relay:
    ports:
      - "8443:8443"
      - "3478:3478/udp"
'@

        $overridePath = New-LocalhostComposeOverrideFile -ComposePath $composePath -ServiceNames @('relay')
        $overrideContent = Get-Content -LiteralPath $overridePath -Raw

        $overrideContent | Should -Match '127\.0\.0\.1:8443:8443'
        $overrideContent | Should -Match '127\.0\.0\.1:3478:3478/udp'
    }

    It 'throws when a target service uses host networking' {
        $composePath = Join-Path $TestDrive 'host.compose.yml'
        Set-Content -Path $composePath -Value @'
services:
  beszel-agent:
    network_mode: host
'@

        {
            New-LocalhostComposeOverrideFile -ComposePath $composePath -ServiceNames @('beszel-agent')
        } | Should -Throw '*network_mode: host*'
    }
}

Describe 'Invoke-DockerCompose' {
    It 'includes additional compose files in dry run output' {
        $preview = Invoke-DockerCompose `
            -File (Join-Path $TestDrive 'base.compose.yml') `
            -AdditionalFiles @((Join-Path $TestDrive 'override.compose.yml')) `
            -Project 'demo-project' `
            -Action 'up -d' `
            -DryRun

        $preview | Should -Match '-f .*base\.compose\.yml'
        $preview | Should -Match '-f .*override\.compose\.yml'
    }
}

Describe 'Get-ServiceAccessDisplayInfo' {
    It 'normalizes loopback bindings to localhost and suppresses LAN output' {
        $result = Get-ServiceAccessDisplayInfo `
            -HostIp '127.0.0.1' `
            -HostPort '5432' `
            -ContainerPort '5432' `
            -Protocol 'tcp' `
            -LanIp '192.168.1.10'

        $result.Local | Should -Be 'localhost:5432'
        $result.Lan | Should -BeNullOrEmpty
    }

    It 'keeps LAN output for all-interface bindings' {
        $result = Get-ServiceAccessDisplayInfo `
            -HostIp '0.0.0.0' `
            -HostPort '30080' `
            -ContainerPort '80' `
            -Protocol 'tcp' `
            -LanIp '192.168.1.10'

        $result.Local | Should -Be 'http://localhost:30080'
        $result.Lan | Should -Be 'http://192.168.1.10:30080'
    }
}
