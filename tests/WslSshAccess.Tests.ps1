Set-StrictMode -Version Latest

Describe 'WSL SSH 宿主与客体入口合同' {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ModulePath = Join-Path $script:ProjectRoot 'windows/wsl/WslSshAccess.psm1'
        $script:EntryPath = Join-Path $script:ProjectRoot 'windows/wsl/Initialize-WslSshAccess.ps1'
        $script:RuntimePath = Join-Path $script:ProjectRoot 'windows/wsl/Invoke-WslSshAccessRefresh.ps1'
        $script:GuestPath = Join-Path $script:ProjectRoot 'linux/wsl/prepare-ssh-access.sh'
        Import-Module $script:ModulePath -Force
        $script:FixtureKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE0U+v3dbT3bF7l6b3Vq7Z1W8pQ0jY8+YqjQ2YyK0fX fixture'
    }

    It '生成稳定且隔离的资源名称' {
        Get-WslSshAccessSafeId -Distribution Ubuntu-22.04 | Should -Be 'ubuntu-22-04'
        $names = Get-WslSshAccessResourceNames -Distribution Ubuntu-22.04

        $names.TaskName | Should -Be 'powershellScripts-WSL-SSH-ubuntu-22-04'
        $names.FirewallRuleName | Should -Be $names.TaskName
        $names.ConfigPath | Should -Match 'ubuntu-22-04\.json$'
        $names.HelperPath | Should -Match 'ubuntu-22-04\.refresh\.ps1$'
    }

    It '只接受单行 OpenSSH 公钥' {
        Test-WslSshAccessPublicKey -PublicKey $script:FixtureKey | Should -BeTrue
        Test-WslSshAccessPublicKey -PublicKey '-----BEGIN OPENSSH PRIVATE KEY-----' | Should -BeFalse
        Test-WslSshAccessPublicKey -PublicKey 'not-a-key' | Should -BeFalse
    }

    It '拒绝无效端口' {
        Test-WslSshAccessPort -Port 22 | Should -BeTrue
        Test-WslSshAccessPort -Port 65535 | Should -BeTrue
        Test-WslSshAccessPort -Port 0 | Should -BeFalse
        Test-WslSshAccessPort -Port 65536 | Should -BeFalse
    }

    It '规范化 Tailscale CIDR 的 provider 掩码表示' {
        ConvertTo-WslSshAccessRemoteAddress -Address '100.64.0.0/255.192.0.0' | Should -Be '100.64.0.0/10'
        ConvertTo-WslSshAccessRemoteAddress -Address LocalSubnet | Should -Be LocalSubnet
    }

    It '兼容数组和逗号分隔的 firewall remote allowlist' {
        $addresses = @(ConvertTo-WslSshAccessRemoteAddresses -Address @('LocalSubnet,100.64.0.0/10'))

        $addresses | Should -Be @('100.64.0.0/10', 'LocalSubnet')
        { ConvertTo-WslSshAccessRemoteAddresses -Address @('Internet') } | Should -Throw
    }

    It '缺失资源生成 Ensure 计划' {
        $state = [pscustomobject]@{
            RuntimeFilesMatch   = $false
            TaskMatches         = $false
            FirewallRuleMatches = $false
            RelayMatches        = $false
        }
        $plan = New-WslSshAccessPlan -Operation Plan -State $state

        $plan.Status | Should -Be 'Preview'
        $plan.Changed | Should -BeTrue
        @($plan.Actions | Where-Object Action -eq Ensure).Count | Should -Be 4
    }

    It '已满足资源生成幂等计划' {
        $state = [pscustomobject]@{
            RuntimeFilesMatch   = $true
            TaskMatches         = $true
            FirewallRuleMatches = $true
            RelayMatches        = $true
        }
        $plan = New-WslSshAccessPlan -Operation Apply -State $state

        $plan.Changed | Should -BeFalse
        @($plan.Actions | Where-Object Action -eq AlreadyPresent).Count | Should -Be 4
    }

    It 'rollback 只处理明确存在的托管资源' {
        $state = [pscustomobject]@{
            TaskExists         = $true
            PortProxyExists    = $false
            RelayListening     = $false
            FirewallRuleExists = $true
            RuntimeFilesExist  = $true
        }
        $plan = New-WslSshAccessPlan -Operation Rollback -State $state

        @($plan.Actions | Where-Object Action -eq Remove).Name | Should -Be @('ScheduledTask', 'FirewallRule', 'RuntimeFiles')
        @($plan.Actions | Where-Object Action -eq AlreadyAbsent).Name | Should -Be @('TcpRelay')
    }

    It '非 Windows 入口输出单个 Blocked JSON document' -Skip:$IsWindows {
        $keyPath = Join-Path $TestDrive 'controller.pub'
        Set-Content -LiteralPath $keyPath -Value $script:FixtureKey -NoNewline
        $output = pwsh -NoProfile -File $script:EntryPath `
            -Distribution Ubuntu-22.04 -WindowsUser mudssky -LinuxUser mudssky `
            -AuthorizedKeyPath $keyPath -OutputFormat Json 2>$null
        $document = $output | Out-String | ConvertFrom-Json

        $LASTEXITCODE | Should -Be 10
        $document.Status | Should -Be 'Blocked'
        $document.Errors.Count | Should -Be 1
    }

    It 'guest 测试模式输出零副作用单文档 Preview' {
        $original = $env:WSL_SSH_ACCESS_TEST_MODE
        try {
            $env:WSL_SSH_ACCESS_TEST_MODE = '1'
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script:FixtureKey))
            $output = bash $script:GuestPath --operation plan --user mudssky --port 22 `
                --authorized-key-base64 $encoded --output-format json
            $document = $output | Out-String | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $document.status | Should -Be 'Preview'
            $document.changed | Should -BeTrue
            $document.keyFingerprint | Should -Be 'SHA256:test'
        }
        finally {
            $env:WSL_SSH_ACCESS_TEST_MODE = $original
        }
    }

    It 'guest apt 安装等待 dpkg lock 且不污染 JSON stdout' {
        $content = Get-Content -LiteralPath $script:GuestPath -Raw

        $content | Should -Match 'DPkg::Lock::Timeout=300'
        $content | Should -Match 'apt-get.+update >&2'
        $content | Should -Match 'apt-get.+install -y openssh-server >&2'
    }

    It 'Windows PowerShell 文件 parser 通过且不包含凭据或 wildcard rollback' {
        foreach ($path in @($script:ModulePath, $script:EntryPath, $script:RuntimePath)) {
            [Convert]::ToHexString([IO.File]::ReadAllBytes($path)[0..2]) | Should -Be 'EFBBBF'
            $tokens = $null
            $errors = $null
            [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
            $content = Get-Content -LiteralPath $path -Raw
            $content | Should -Not -Match 'PRIVATE KEY-----'
            $content | Should -Not -Match 'Unregister-ScheduledTask.+\*'
            $content | Should -Not -Match 'Remove-NetFirewallRule.+\*'
        }
        (Get-Content -LiteralPath $script:RuntimePath -Raw) | Should -Match 'persistent WSL SSH TCP relay is running'
        (Get-Content -LiteralPath $script:RuntimePath -Raw) | Should -Match 'systemctl restart ssh'
        (Get-Content -LiteralPath $script:RuntimePath -Raw) | Should -Match "sleep', 'infinity'"
        (Get-Content -LiteralPath $script:RuntimePath -Raw) | Should -Match 'WSL keepalive process exited'
    }

    It 'runtime relay 使用每轮解析的 WSL IPv4 连接 guest sshd' {
        $content = Get-Content -LiteralPath $script:RuntimePath -Raw

        $content | Should -Match '\$client\.Connect\(\$wslIPv4, \[int\]\$config\.guestPort\)'
        $content | Should -Match '\[WslSshTcpRelay\]::Run\(.+\$wslIPv4, \[int\]\$config\.guestPort'
        $content | Should -Not -Match '\$client\.Connect\(''127\.0\.0\.1'''
        $content | Should -Not -Match '\[WslSshTcpRelay\]::Run\(.+''127\.0\.0\.1'''
    }
}
