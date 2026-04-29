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
            'Split-RcloneOpsArguments',
            'Get-RcloneOpsOptionWithConfig'
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

    It '能解析透传参数与布尔开关' {
        $parsed = Split-RcloneOpsArguments -ArgumentList @('source', 'dest', '--run', '--', '--progress')

        $parsed.Positionals | Should -Be @('source', 'dest')
        $parsed.Flags['run'] | Should -BeTrue
        $parsed.Passthrough | Should -Be @('--progress')
    }
}
