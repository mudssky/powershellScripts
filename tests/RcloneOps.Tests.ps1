Set-StrictMode -Version Latest

BeforeAll {
    $script:RcloneOpsScriptPath = Join-Path $PSScriptRoot '..' 'config' 'service' 'oss' 'rclone' 'rclone-ops.ps1'
    $script:OriginalSkipMainFlag = [Environment]::GetEnvironmentVariable('RCLONE_OPS_SKIP_MAIN', 'Process')
    $script:OriginalCloudMainAccessKeyId = [Environment]::GetEnvironmentVariable('CLOUD_MAIN_ACCESS_KEY_ID', 'Process')
    $script:OriginalCloudMainSecretAccessKey = [Environment]::GetEnvironmentVariable('CLOUD_MAIN_SECRET_ACCESS_KEY', 'Process')
    $env:RCLONE_OPS_SKIP_MAIN = '1'
    . $script:RcloneOpsScriptPath
}

AfterAll {
    if ($null -eq $script:OriginalSkipMainFlag) {
        Remove-Item Env:\RCLONE_OPS_SKIP_MAIN -ErrorAction SilentlyContinue
    }
    else {
        $env:RCLONE_OPS_SKIP_MAIN = $script:OriginalSkipMainFlag
    }

    if ($null -eq $script:OriginalCloudMainAccessKeyId) {
        Remove-Item Env:\CLOUD_MAIN_ACCESS_KEY_ID -ErrorAction SilentlyContinue
    }
    else {
        $env:CLOUD_MAIN_ACCESS_KEY_ID = $script:OriginalCloudMainAccessKeyId
    }

    if ($null -eq $script:OriginalCloudMainSecretAccessKey) {
        Remove-Item Env:\CLOUD_MAIN_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
    }
    else {
        $env:CLOUD_MAIN_SECRET_ACCESS_KEY = $script:OriginalCloudMainSecretAccessKey
    }

    foreach ($functionName in @(
            'ConvertTo-RcloneOpsConfig',
            'Get-RcloneOpsRemoteName',
            'Read-RcloneOpsConfigValues',
            'Resolve-RcloneOpsEnvPlaceholder',
            'ConvertTo-RcloneOpsMountDefinitions',
            'New-RcloneOpsMountArguments',
            'New-RcloneOpsManualMountPidFile',
            'Test-RcloneOpsMountPoint',
            'Dismount-RcloneOpsMount',
            'Stop-RcloneOpsWebUi',
            'Invoke-RcloneOpsProcess',
            'Split-RcloneOpsArguments',
            'Get-RcloneOpsOptionWithConfig',
            'Get-RcloneOpsWebUiLogFile'
        )) {
        Remove-Item -Path ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
    }
}

Describe 'rclone-ops.ps1 JSON 配置生成逻辑' {
    It '能从 JSON remotes 数组生成 remote' {
        $jsonPath = Join-Path $TestDrive 'rclone.config.json'
        Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM -Value @'
{
  "remotes": [
    {
      "name": "cloud-main",
      "type": "s3",
      "provider": "Other",
      "access_key_id": "main-id",
      "secret_access_key": "main-secret",
      "endpoint": "https://s3.example.com",
      "region": "auto"
    },
    {
      "name": "archive",
      "type": "s3",
      "provider": "Other",
      "access_key_id": "archive-id",
      "secret_access_key": "archive-secret",
      "endpoint": "http://127.0.0.1:9000",
      "force_path_style": "true"
    }
  ]
}
'@

        $values = Read-RcloneOpsConfigValues -ConfigPath $jsonPath
        $config = ConvertTo-RcloneOpsConfig -ConfigValues $values
        $names = Get-RcloneOpsRemoteName -Content $config

        $names | Should -Be @('cloud-main', 'archive')
        $config | Should -Match '\[cloud-main\]'
        $config | Should -Match 'provider = Other'
        $config | Should -Match 'force_path_style = true'
    }

    It '能替换 JSON 字符串中的环境变量占位符' {
        $env:CLOUD_MAIN_ACCESS_KEY_ID = 'env-main-id'
        $env:CLOUD_MAIN_SECRET_ACCESS_KEY = 'env-main-secret'
        $jsonPath = Join-Path $TestDrive 'rclone.env-placeholders.json'
        Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM -Value @'
{
  "remotes": [
    {
      "name": "cloud-main",
      "type": "s3",
      "provider": "Other",
      "access_key_id": "${CLOUD_MAIN_ACCESS_KEY_ID}",
      "secret_access_key": "${CLOUD_MAIN_SECRET_ACCESS_KEY}",
      "endpoint": "https://s3.example.com"
    }
  ]
}
'@

        $values = Read-RcloneOpsConfigValues -ConfigPath $jsonPath
        $config = ConvertTo-RcloneOpsConfig -ConfigValues $values

        $config | Should -Match 'access_key_id = env-main-id'
        $config | Should -Match 'secret_access_key = env-main-secret'
    }

    It '缺少环境变量占位符时抛出清晰错误' {
        Remove-Item Env:\CLOUD_MAIN_ACCESS_KEY_ID -ErrorAction SilentlyContinue

        { Resolve-RcloneOpsEnvPlaceholder -Value '${CLOUD_MAIN_ACCESS_KEY_ID}' -Context 'remotes[0].access_key_id' } |
            Should -Throw '环境变量未设置: CLOUD_MAIN_ACCESS_KEY_ID*'
    }

    It '拒绝旧平铺配置格式' {
        $jsonPath = Join-Path $TestDrive 'flat.config.json'
        Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM -Value @'
{
  "RCLONE_REMOTE_NAMES": "cloud-main",
  "RCLONE_REMOTE_CLOUD_MAIN_TYPE": "s3"
}
'@

        $values = Read-RcloneOpsConfigValues -ConfigPath $jsonPath

        { ConvertTo-RcloneOpsConfig -ConfigValues $values } | Should -Throw '旧平铺格式已不支持*'
    }

    It '拒绝非 JSON 配置文件' {
        $envPath = Join-Path $TestDrive '.env.local'
        Set-Content -LiteralPath $envPath -Encoding utf8NoBOM -Value 'RCLONE_REMOTE_NAMES=cloud-main'

        { Read-RcloneOpsConfigValues -ConfigPath $envPath } | Should -Throw 'rclone-ops 仅支持 JSON 主配置*'
    }


    It '能从 JSON webui section 读取 RC 密码' {
        $env:RCLONE_RC_PASS = 'json-rc-pass'
        $values = @{
            webui = [pscustomobject]@{
                addr = '100.64.0.1:5572'
                user = 'admin'
                pass = '${RCLONE_RC_PASS}'
            }
        }

        $password = Get-RcloneOpsOptionWithConfig -Flags @{} -Name 'pass' -EnvName 'UNUSED_RCLONE_RC_PASS' -ConfigValues $values -Section 'webui' -ConfigName 'pass' -DefaultValue ''

        $password | Should -Be 'json-rc-pass'
    }

    It '能从 JSON webui section 读取后台日志路径' {
        $values = @{
            webui = [pscustomobject]@{
                'log-file' = 'logs/webui.log'
            }
        }

        $logFile = Get-RcloneOpsWebUiLogFile -Flags @{} -ConfigValues $values -BasePath $TestDrive

        $logFile | Should -Be (Join-Path $TestDrive 'logs/webui.log')
    }

    It '能解析透传参数与布尔开关' {
        $parsed = Split-RcloneOpsArguments -ArgumentList @('source', 'dest', '--run', '--', '--progress')

        $parsed.Positionals | Should -Be @('source', 'dest')
        $parsed.Flags['run'] | Should -BeTrue
        $parsed.Passthrough | Should -Be @('--progress')
    }

    It '能从 JSON mounts 生成 enabled profile 并解析本地路径' {
        $values = @{
            mounts = @(
                [pscustomobject]@{
                    name       = 'cloud-main'
                    enabled    = $true
                    remote     = 'cloud-main:bucket'
                    mountPoint = 'mounts/cloud-main'
                    options    = [pscustomobject]@{
                        'vfs-cache-mode'       = 'writes'
                        'cache-dir'            = '.runtime/cache/cloud-main'
                        'vfs-fast-fingerprint' = $true
                    }
                },
                [pscustomobject]@{
                    name       = 'archive'
                    enabled    = $false
                    remote     = 'archive:'
                    mountPoint = 'mounts/archive'
                }
            )
        }

        $definitions = ConvertTo-RcloneOpsMountDefinitions -ConfigValues $values -BasePath $TestDrive

        $definitions.Count | Should -Be 1
        $definitions[0].Name | Should -Be 'cloud-main'
        $definitions[0].Remote | Should -Be 'cloud-main:bucket'
        $definitions[0].MountPoint | Should -Be (Join-Path $TestDrive 'mounts/cloud-main')
        $definitions[0].PidFile | Should -Match 'mounts.cloud-main\.pid|mounts/cloud-main\.pid'
    }

    It '能将 mount options 转换为 rclone 参数' {
        $definition = [pscustomobject]@{
            Name       = 'cloud-main'
            Remote     = 'cloud-main:'
            MountPoint = Join-Path $TestDrive 'mounts/cloud-main'
            Options    = @{
                'vfs-cache-mode'       = 'writes'
                'cache-dir'            = '.runtime/cache/cloud-main'
                'vfs-fast-fingerprint' = $true
                'read-only'            = $false
                'log-file'             = '.runtime/logs/mount-cloud-main.log'
            }
        }

        $arguments = New-RcloneOpsMountArguments -Definition $definition -ConfigPath 'rclone.conf' -BasePath $TestDrive

        $arguments | Should -Contain 'mount'
        $arguments | Should -Contain 'cloud-main:'
        $arguments | Should -Contain "--config=rclone.conf"
        $arguments | Should -Contain '--vfs-cache-mode=writes'
        $arguments | Should -Contain '--vfs-fast-fingerprint'
        $arguments | Should -Not -Contain '--read-only'
        $arguments | Should -Contain ("--cache-dir={0}" -f (Join-Path $TestDrive '.runtime/cache/cloud-main'))
        $arguments | Should -Contain ("--log-file={0}" -f (Join-Path $TestDrive '.runtime/logs/mount-cloud-main.log'))
    }

    It '缺少 mount 必填字段时抛出清晰错误' {
        $values = @{
            mounts = @(
                [pscustomobject]@{
                    name       = 'broken'
                    mountPoint = 'mounts/broken'
                }
            )
        }

        { ConvertTo-RcloneOpsMountDefinitions -ConfigValues $values -BasePath $TestDrive } |
            Should -Throw '*缺少 remote*'
    }

    It 'mounts 缺失或全部禁用时返回空集合' {
        @(ConvertTo-RcloneOpsMountDefinitions -ConfigValues @{} -BasePath $TestDrive).Count | Should -Be 0
        @(ConvertTo-RcloneOpsMountDefinitions -ConfigValues @{
                mounts = @(
                    [pscustomobject]@{
                        name       = 'disabled'
                        enabled    = $false
                        remote     = 'disabled:'
                        mountPoint = 'mounts/disabled'
                    }
                )
            } -BasePath $TestDrive).Count | Should -Be 0
    }

    It '手工后台 mount 使用独立 PID 文件' {
        $pidFile = New-RcloneOpsManualMountPidFile -Positionals @('cloud-main:', 'mounts/cloud-main')

        $pidFile | Should -Match 'manual-mounts_cloud-main\.pid'
        $pidFile | Should -Not -Match 'mount\.pid$'
    }

    It '卸载普通目录时跳过并返回成功' {
        $plainDirectory = Join-Path $TestDrive 'plain-directory'
        New-Item -ItemType Directory -Path $plainDirectory -Force | Out-Null

        $exitCode = Dismount-RcloneOpsMount -Positionals @($plainDirectory)

        $exitCode | Should -Be 0
    }

    It '停止 WebUI 时会清理过期 PID 文件' {
        $runtimeDirectory = Join-Path (Split-Path -Parent $script:RcloneOpsScriptPath) '.runtime'
        $pidFile = Join-Path $runtimeDirectory 'webui.pid'
        New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
        Set-Content -LiteralPath $pidFile -Value '999999' -Encoding utf8NoBOM

        Stop-RcloneOpsWebUi

        Test-Path -LiteralPath $pidFile | Should -BeFalse
    }

    It 'up 会强制刷新生成 rclone.conf' {
        $commandText = (Get-Command Start-RcloneOpsStack).ScriptBlock.ToString()

        $commandText | Should -Match '\[''overwrite''\]\s*=\s*\$true'
        $commandText | Should -Not -Match 'if \(-not \(Test-Path -LiteralPath \$context\.ConfigPath'
    }

    It '后台进程快速退出时清理 PID 并返回失败' {
        $pidFile = Join-Path $TestDrive 'failed.pid'
        $logFile = Join-Path $TestDrive 'failed.log'
        Set-Content -LiteralPath $logFile -Value '模拟后台失败日志' -Encoding utf8NoBOM
        # 使用平台原生命令构造稳定的快速失败进程，避免 Windows CI 中 pwsh 冷启动超过探测窗口。
        $failedProcess = if ($IsWindows) {
            @{
                FilePath         = 'cmd.exe'
                Arguments        = @('/d', '/c', 'exit 7')
                ExpectedExitCode = 7
            }
        }
        else {
            @{
                FilePath         = 'false'
                Arguments        = @()
                ExpectedExitCode = 1
            }
        }

        $warningMessages = @()
        $exitCode = Invoke-RcloneOpsProcess -FilePath $failedProcess.FilePath -Arguments $failedProcess.Arguments -Background -PidFile $pidFile -FailureLogFile $logFile -WarningVariable warningMessages

        $exitCode | Should -Be $failedProcess.ExpectedExitCode
        Test-Path -LiteralPath $pidFile | Should -BeFalse
        ($warningMessages -join "`n") | Should -Match '模拟后台失败日志'
    }
}
