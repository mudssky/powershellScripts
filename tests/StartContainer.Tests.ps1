Set-StrictMode -Version Latest

function script:Get-ComposeServiceBlock {
    param(
        [string]$ComposePath,
        [string]$ServiceName
    )

    $lines = Get-Content -LiteralPath $ComposePath
    $startIndex = -1

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^\s{2}$([regex]::Escape($ServiceName)):\s*$") {
            $startIndex = $index
            break
        }
    }

    if ($startIndex -lt 0) {
        throw "未找到 compose 服务块: $ServiceName"
    }

    $blockLines = New-Object System.Collections.Generic.List[string]
    for ($index = $startIndex; $index -lt $lines.Count; $index++) {
        if ($index -gt $startIndex -and $lines[$index] -match '^\s{2}[A-Za-z0-9\-_]+:\s*$') {
            break
        }

        $blockLines.Add($lines[$index])
    }

    return ($blockLines -join "`n")
}

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:OriginalSkipStartContainerMain = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_START_CONTAINER_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_START_CONTAINER_MAIN = '1'

    . (Join-Path $script:RepoRoot 'scripts/pwsh/devops/start-container.ps1')
}

AfterAll {
    if ($null -eq $script:OriginalSkipStartContainerMain) {
        Remove-Item Env:\PWSH_TEST_SKIP_START_CONTAINER_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_START_CONTAINER_MAIN', $script:OriginalSkipStartContainerMain, 'Process')
    }
}

Describe 'Get-ServiceDefaultUser' {
    It 'postgre 默认使用 postgres' {
        Get-ServiceDefaultUser -ServiceName 'postgre' | Should -Be 'postgres'
    }

    It 'paradedb 默认使用 postgres' {
        Get-ServiceDefaultUser -ServiceName 'paradedb' | Should -Be 'postgres'
    }

    It '非 PostgreSQL 服务保持 root' {
        Get-ServiceDefaultUser -ServiceName 'minio' | Should -Be 'root'
    }
}

Describe 'Resolve-ServiceDefaultUser' {
    It '显式传入默认用户时仍使用传入值' {
        Resolve-ServiceDefaultUser -ServiceName 'paradedb' -CliDefaultUser 'custom-user' -EnvironmentDefaultUser '' | Should -Be 'custom-user'
    }

    It '普通服务在环境变量中已有 DEFAULT_USER 时保持原值' {
        Resolve-ServiceDefaultUser -ServiceName 'minio' -CliDefaultUser '' -EnvironmentDefaultUser 'env-user' | Should -Be 'env-user'
    }
}

Describe 'docker compose postgres defaults' {
    It 'postgre 配置显式声明 POSTGRES_USER' {
        $composePath = Join-Path $script:RepoRoot 'config/dockerfiles/compose/docker-compose.yml'
        $postgreBlock = Get-ComposeServiceBlock -ComposePath $composePath -ServiceName 'postgre'

        $postgreBlock | Should -Match 'POSTGRES_USER: \$\{DEFAULT_USER:-postgres\}'
    }

    It 'postgre 健康检查复用同一默认用户名变量' {
        $composePath = Join-Path $script:RepoRoot 'config/dockerfiles/compose/docker-compose.yml'
        $postgreBlock = Get-ComposeServiceBlock -ComposePath $composePath -ServiceName 'postgre'

        $postgreBlock | Should -Match 'pg_isready -U \$\{DEFAULT_USER:-postgres\}'
    }
}

Describe 'docker compose shared template' {
    It 'no longer exposes derper after the dedicated template is introduced' {
        $composePath = Join-Path $script:RepoRoot 'config/dockerfiles/compose/docker-compose.yml'

        {
            Get-ComposeServiceBlock -ComposePath $composePath -ServiceName 'derper'
        } | Should -Throw '*未找到 compose 服务块: derper*'
    }
}

Describe 'Get-ComposeServiceNames' {
    It 'does not list derper after it moves to config/network/tailscale/derp' {
        $composePath = Join-Path $script:RepoRoot 'config/dockerfiles/compose/docker-compose.yml'
        $replicaComposePath = Join-Path $script:RepoRoot 'config/dockerfiles/compose/mongo-repl.compose.yml'

        Get-ComposeServiceNames -ComposePath $composePath -ReplicaComposePath $replicaComposePath | Should -Not -Contain 'derper'
    }
}

Describe 'start-container script help surface' {
    It 'does not advertise derper anymore' {
        $scriptContent = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/pwsh/devops/start-container.ps1') -Raw

        $scriptContent | Should -Not -Match '(?m)^\s*-\s+derper:'
        $scriptContent | Should -Not -Match '"derper"'
    }
}
