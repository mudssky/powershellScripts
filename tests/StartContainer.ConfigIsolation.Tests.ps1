Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:StartContainerScriptPath = Join-Path $script:RepoRoot 'scripts/pwsh/devops/start-container.ps1'
    $script:OriginalSkipFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_START_CONTAINER_MAIN', 'Process')
    $script:OriginalDefaultUser = [Environment]::GetEnvironmentVariable('DEFAULT_USER', 'Process')
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

    if ($null -eq $script:OriginalDefaultUser) {
        Remove-Item Env:\DEFAULT_USER -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('DEFAULT_USER', $script:OriginalDefaultUser, 'Process')
    }
}

Describe 'Resolve-ServiceComposeConfiguration' {
    It 'database services ignore stale process DEFAULT_USER values' {
        $composeDir = Join-Path $TestDrive 'compose-db'
        New-Item -ItemType Directory -Path $composeDir -Force | Out-Null
        Set-Content -Path (Join-Path $composeDir '.env') -Value 'DEFAULT_PASSWORD=file-password'
        $env:DEFAULT_USER = 'root'

        $result = Resolve-ServiceComposeConfiguration `
            -ServiceName 'paradedb' `
            -ComposeDir $composeDir `
            -CliEnv @{} `
            -DataPath '/tmp/docker-data' `
            -DefaultUser '' `
            -DefaultPassword '12345678' `
            -RestartPolicy 'unless-stopped' `
            -ProjectName 'dev-paradedb'

        $result.Values.DEFAULT_USER | Should -Be 'postgres'
        $result.Sources.DEFAULT_USER | Should -Be 'ServiceDefaults'
    }

    It 'normal services still accept process DEFAULT_USER values' {
        $composeDir = Join-Path $TestDrive 'compose-minio'
        New-Item -ItemType Directory -Path $composeDir -Force | Out-Null
        $env:DEFAULT_USER = 'root'

        $result = Resolve-ServiceComposeConfiguration `
            -ServiceName 'minio' `
            -ComposeDir $composeDir `
            -CliEnv @{} `
            -DataPath '/tmp/docker-data' `
            -DefaultUser '' `
            -DefaultPassword '12345678' `
            -RestartPolicy 'unless-stopped' `
            -ProjectName 'dev-minio'

        $result.Values.DEFAULT_USER | Should -Be 'root'
        $result.Sources.DEFAULT_USER | Should -Be 'ProcessEnv'
    }
}

Describe 'Invoke-DockerCompose' {
    It 'does not leak scoped env values after a dry run' {
        Remove-Item Env:\DEFAULT_USER -ErrorAction SilentlyContinue

        $null = Invoke-DockerCompose `
            -File (Join-Path $TestDrive 'demo-compose.yml') `
            -Project 'demo-project' `
            -Profiles @('paradedb') `
            -Action 'up -d' `
            -Environment @{ DEFAULT_USER = 'postgres' } `
            -DryRun

        Test-Path Env:\DEFAULT_USER | Should -Be $false
    }
}

Describe 'Get-DatabaseStateWarningMessage' {
    It 'returns a warning when a ParadeDB data directory already contains PG_VERSION' {
        $dataPath = Join-Path $TestDrive 'docker-data'
        $databasePath = [System.IO.Path]::Combine($dataPath, 'paradedb', 'data')
        New-Item -ItemType Directory -Path $databasePath -Force | Out-Null
        Set-Content -Path (Join-Path $databasePath 'PG_VERSION') -Value '17'

        $message = Get-DatabaseStateWarningMessage -ServiceName 'paradedb' -DataPath $dataPath

        $message | Should -Match '仅影响新初始化实例'
        $message | Should -Match 'paradedb'
    }
}
