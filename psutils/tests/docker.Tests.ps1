BeforeAll {
    $script:DockerModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\modules\docker.psm1'))
    Import-Module $script:DockerModulePath -Force
}

Describe 'Docker Compose helper' {
    It '生成 compose 基础参数并包含存在的 env 文件' {
        $root = Join-Path $TestDrive 'compose-root'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $composeFile = Join-Path $root 'compose.yaml'
        $envFile = Join-Path $root '.env.local'
        Set-Content -LiteralPath $composeFile -Encoding utf8NoBOM -Value 'services: {}'
        Set-Content -LiteralPath $envFile -Encoding utf8NoBOM -Value 'A=1'

        $args = Get-DockerComposeBaseArgs -ComposeFile $composeFile -ProjectDirectory $root -EnvFile $envFile

        $args | Should -Be @('compose', '-f', $composeFile, '--project-directory', $root, '--env-file', $envFile)
    }

    It 'env 文件不存在时省略 env-file 参数' {
        $root = Join-Path $TestDrive 'compose-root-no-env'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $composeFile = Join-Path $root 'compose.yaml'
        Set-Content -LiteralPath $composeFile -Encoding utf8NoBOM -Value 'services: {}'

        $args = Get-DockerComposeBaseArgs -ComposeFile $composeFile -ProjectDirectory $root -EnvFile (Join-Path $root '.env.local')

        $args | Should -Not -Contain '--env-file'
    }

    It 'DryRun 返回带环境变量前缀的预览命令' {
        $preview = Invoke-DockerComposeCommand -ComposeArgs @('compose', '-f', '/tmp/demo.yaml', 'build') -Environment @{ BUILDKIT_PROGRESS = 'plain' } -DryRun

        $preview | Should -Be 'BUILDKIT_PROGRESS=plain docker compose -f /tmp/demo.yaml build'
    }

    It 'SkipDockerCheck 时只校验 compose 文件存在' {
        $composeFile = Join-Path $TestDrive 'compose.yaml'
        Set-Content -LiteralPath $composeFile -Encoding utf8NoBOM -Value 'services: {}'

        { Assert-DockerComposeReady -ComposeFile $composeFile -EnvFile (Join-Path $TestDrive '.env.local') -SkipDockerCheck } |
            Should -Not -Throw
    }
}
