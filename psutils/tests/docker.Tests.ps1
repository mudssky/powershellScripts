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

Describe 'WSL Docker wrapper helper' {
    BeforeEach {
        $script:OriginalWslDockerEnv = @{
            WSL_DOCKER_DISTRO         = [Environment]::GetEnvironmentVariable('WSL_DOCKER_DISTRO', 'Process')
            WSL_DOCKER_FORWARD_ENV    = [Environment]::GetEnvironmentVariable('WSL_DOCKER_FORWARD_ENV', 'Process')
            WSL_DOCKER_PATH_ENV       = [Environment]::GetEnvironmentVariable('WSL_DOCKER_PATH_ENV', 'Process')
            WSL_DOCKER_WRAPPER_ACTIVE = [Environment]::GetEnvironmentVariable('WSL_DOCKER_WRAPPER_ACTIVE', 'Process')
            WSL_DOCKER_WRAPPER_DISTRO = [Environment]::GetEnvironmentVariable('WSL_DOCKER_WRAPPER_DISTRO', 'Process')
            DATA_PATH                 = [Environment]::GetEnvironmentVariable('DATA_PATH', 'Process')
        }

        Remove-Item Env:\WSL_DOCKER_DISTRO -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_DOCKER_FORWARD_ENV -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_DOCKER_PATH_ENV -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_DOCKER_WRAPPER_ACTIVE -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_DOCKER_WRAPPER_DISTRO -ErrorAction SilentlyContinue
        Remove-Item Env:\DATA_PATH -ErrorAction SilentlyContinue
    }

    AfterEach {
        foreach ($entry in $script:OriginalWslDockerEnv.GetEnumerator()) {
            if ($null -eq $entry.Value) {
                Remove-Item "Env:$($entry.Key)" -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
            }
        }
        Remove-Item Function:\docker -ErrorAction SilentlyContinue
        Remove-Item Function:\wsl.exe -ErrorAction SilentlyContinue
    }

    It '检测不到 WSL 时不启用 wrapper' {
        $enabled = Enable-WslDockerWrapper -WslCommand 'missing-wsl.exe'

        $enabled | Should -BeFalse
        Get-Command docker -CommandType Function -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'Docker Desktop daemon 可用时不启用 wrapper' {
        function global:docker {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
            if ($Args -join ' ' -eq 'info --format {{json .}}') {
                '{"OperatingSystem":"Docker Desktop"}'
                $global:LASTEXITCODE = 0
                return
            }
            $global:LASTEXITCODE = 1
        }

        $enabled = Enable-WslDockerWrapper -DockerCommand 'docker' -WslCommand 'wsl.exe' -Force

        $enabled | Should -BeFalse
    }

    It 'WSL 内非 Docker Desktop Engine 可用时启用 wrapper' {
        function global:wsl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
            $joined = $Args -join ' '
            if ($joined -eq '--status') {
                'Default Distribution: Ubuntu-24.04'
                $global:LASTEXITCODE = 0
                return
            }
            if ($joined -eq '-d Ubuntu-24.04 -- docker info --format {{json .}}') {
                '{"OperatingSystem":"Ubuntu 24.04"}'
                $global:LASTEXITCODE = 0
                return
            }
            $global:LASTEXITCODE = 1
        }

        $enabled = Enable-WslDockerWrapper -DockerCommand 'docker' -WslCommand 'wsl.exe' -Force

        $enabled | Should -BeTrue
        $env:WSL_DOCKER_WRAPPER_ACTIVE | Should -Be '1'
        $env:WSL_DOCKER_WRAPPER_DISTRO | Should -Be 'Ubuntu-24.04'
        Get-Command docker -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It '注册后的 docker 函数支持原始 docker run 命令形态' {
        function global:wsl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
            $joined = $Args -join ' '
            if ($joined -eq '--status') {
                'Default Distribution: Ubuntu-24.04'
                $global:LASTEXITCODE = 0
                return
            }
            if ($joined -eq '-d Ubuntu-24.04 -- docker info --format {{json .}}') {
                '{"OperatingSystem":"Ubuntu 24.04"}'
                $global:LASTEXITCODE = 0
                return
            }
            if ($joined -like '-d Ubuntu-24.04 -- wslpath -a *') {
                $inputPath = $Args[-1]
                if ($inputPath -match '^[A-Za-z]:[\\/]') {
                    '/mnt/c/workspace'
                }
                else {
                    $inputPath
                }
                $global:LASTEXITCODE = 0
                return
            }

            $script:LastWslDockerArgs = @($Args)
            $global:LASTEXITCODE = 0
        }

        Enable-WslDockerWrapper -DockerCommand 'docker' -WslCommand 'wsl.exe' -Force | Should -BeTrue

        docker run --rm alpine:3.20 echo ok
        $expectedWorkingDirectory = ConvertTo-WslDockerPath -Path (Get-Location).Path -Distro 'Ubuntu-24.04'

        $script:LastWslDockerArgs | Should -Be @(
            '-d'
            'Ubuntu-24.04'
            '--cd'
            $expectedWorkingDirectory
            '--'
            'docker'
            'run'
            '--rm'
            'alpine:3.20'
            'echo'
            'ok'
        )
    }

    It '转换 compose 文件、env 文件、volume 与 bind mount 参数' {
        $composeFile = Join-Path $TestDrive 'docker-compose.yml'
        $envFile = Join-Path $TestDrive '.env'
        $dataDir = Join-Path $TestDrive 'data'
        Set-Content -LiteralPath $composeFile -Encoding utf8NoBOM -Value 'services: {}'
        Set-Content -LiteralPath $envFile -Encoding utf8NoBOM -Value 'A=1'
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

        function global:wsl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
            $inputPath = $Args[-1]
            $drive = $inputPath.Substring(0, 1).ToLowerInvariant()
            $rest = $inputPath.Substring(2).Replace('\', '/')
            "/mnt/$drive$rest"
            $global:LASTEXITCODE = 0
        }

        Push-Location $TestDrive
        try {
            $args = ConvertTo-WslDockerArgument -Distro 'Ubuntu-24.04' -Arguments @(
                'compose'
                '-f'
                '.\docker-compose.yml'
                '--env-file=.env'
                '-v'
                '.\data:/data:ro'
                '--mount=type=bind,src=.\data,target=/mnt/data'
            )
        }
        finally {
            Pop-Location
        }

        $expectedRoot = ConvertTo-WslDockerPath -Path $TestDrive -Distro 'Ubuntu-24.04'
        $args | Should -Be @(
            'compose'
            '-f'
            "$expectedRoot/docker-compose.yml"
            "--env-file=$expectedRoot/.env"
            '-v'
            "$expectedRoot/data:/data:ro"
            "--mount=type=bind,src=$expectedRoot/data,target=/mnt/data"
        )
    }

    It '透传 DATA_PATH 并转换为 WSL 路径' {
        $dataDir = Join-Path $TestDrive 'data'
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        $env:DATA_PATH = $dataDir

        function global:wsl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
            $inputPath = $Args[-1]
            $drive = $inputPath.Substring(0, 1).ToLowerInvariant()
            $rest = $inputPath.Substring(2).Replace('\', '/')
            "/mnt/$drive$rest"
            $global:LASTEXITCODE = 0
        }

        $envArgs = InModuleScope docker {
            Get-WslDockerEnvironmentArgument -Distro 'Ubuntu-24.04'
        }
        $expectedDataPath = ConvertTo-WslDockerPath -Path $dataDir -Distro 'Ubuntu-24.04'

        $envArgs | Should -Contain "DATA_PATH=$expectedDataPath"
    }

    It '不转换普通位置参数中的服务名或镜像名' {
        Set-Content -LiteralPath (Join-Path $TestDrive 'api') -Encoding utf8NoBOM -Value 'not a path argument'

        Push-Location $TestDrive
        try {
            $args = ConvertTo-WslDockerArgument -Distro 'Ubuntu-24.04' -Arguments @('compose', 'restart', 'api')
        }
        finally {
            Pop-Location
        }

        $args | Should -Be @('compose', 'restart', 'api')
    }
}
