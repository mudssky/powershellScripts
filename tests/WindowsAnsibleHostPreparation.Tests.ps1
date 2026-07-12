Set-StrictMode -Version Latest

Describe 'Windows Ansible 被控端准备合同' {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ModulePath = Join-Path $script:ProjectRoot 'windows/bootstrap/WindowsAnsibleHostPreparation.psm1'
        $script:BootstrapModulePath = Join-Path $script:ProjectRoot 'windows/bootstrap/WindowsBootstrap.psm1'
        $script:EntryPath = Join-Path $script:ProjectRoot 'windows/bootstrap/Prepare-WindowsAnsibleHost.ps1'
        Import-Module $script:ModulePath -Force
    }

    It '按 Failed 优先于 Blocked 汇总退出码' {
        $results = @(
            New-WindowsAnsiblePreparationResult -Name login -Status Blocked -ExitCode 10
        )
        Get-WindowsAnsiblePreparationExitCode -Result $results | Should -Be 10

        $results += New-WindowsAnsiblePreparationResult -Name install -Status Failed -ExitCode 1
        Get-WindowsAnsiblePreparationExitCode -Result $results | Should -Be 1
    }

    It '为缺失 Tailscale 和 OpenSSH 生成自动安装计划与登录步骤' {
        $state = [pscustomobject]@{
            IsWindows               = $true
            HostName                = 'iminipro820'
            UserName                = 'mudssky'
            IsAdministrator         = $true
            IsAdministratorsMember  = $true
            WingetAvailable         = $true
            TailscaleInstalled      = $false
            TailscaleCommand        = $null
            TailscaleIPv4           = ''
            OpenSshInstalled        = $false
            SshdExists              = $false
            SshdRunning             = $false
            SshdAutomatic           = $false
            DefaultShell            = ''
            PortListening           = $false
            FirewallEnabled         = $false
            FirewallRuleExists      = $false
        }

        $plan = New-WindowsAnsibleHostPreparationPlan -State $state

        ($plan.Results | Where-Object Name -eq TailscaleInstall).Message | Should -Match 'winget install'
        ($plan.Results | Where-Object Name -eq OpenSshServer).Message | Should -Match 'Add-WindowsCapability'
        @($plan.ManualSteps.Name) | Should -Contain 'LoginTailscale'
        ($plan.ManualSteps | Where-Object Name -eq LoginTailscale).VerifyCommand | Should -Match 'tailscale.exe.*ip -4'
    }

    It '真实执行非管理员时先返回提升步骤' {
        $state = [pscustomobject]@{
            IsWindows               = $true
            HostName                = 'iminipro820'
            UserName                = 'mudssky'
            IsAdministrator         = $false
            IsAdministratorsMember  = $true
            WingetAvailable         = $true
            TailscaleInstalled      = $true
            TailscaleCommand        = 'tailscale.exe'
            TailscaleIPv4           = '100.125.34.90'
            OpenSshInstalled        = $false
            SshdExists              = $false
            SshdRunning             = $false
            SshdAutomatic           = $false
            DefaultShell            = ''
            PortListening           = $false
            FirewallEnabled         = $false
            FirewallRuleExists      = $false
        }

        $plan = New-WindowsAnsibleHostPreparationPlan -State $state -Apply

        ($plan.Results | Where-Object Name -eq Administrator).Status | Should -Be 'Blocked'
        @($plan.ManualSteps.Name) | Should -Contain 'RunElevated'
    }

    It '生成 self-hosted-compose 可直接消费的控制端配置' {
        $config = New-WindowsAnsibleControllerConfig -InventoryHost iminipro820 -HostName IMINI820PRO `
            -UserName mudssky -TailscaleIPv4 100.125.34.90 -SshPort 22 -SshReady $true

        $config.Ready | Should -BeTrue
        $config.InventoryHost | Should -Be 'iminipro820'
        $config.Groups | Should -Be @('windows', 'powershell_scripts_targets')
        $config.PublicHostVars.ansible_host | Should -Be '100.125.34.90'
        $config.PublicHostVars.ansible_user | Should -Be 'mudssky'
        $config.SshBootstrapVars.ansible_connection | Should -Be 'ssh'
        $config.SshBootstrapVars.ansible_shell_type | Should -Be 'powershell'
        $config.PrivateHostVarKeys | Should -Contain 'ansible_password'
        @($config.ControllerCommands | Where-Object { $_ -match 'provision.*powershell_scripts_apply=true' }).Count | Should -Be 1
        $config.ControllerCommands[-1] | Should -Match 'powershell-scripts-verify.yml'
    }

    It 'sshd 已满足时 Apply 不报告 Changed' {
        $operation = Resolve-WindowsAnsibleSshdServiceOperation -SshdAutomatic $true -SshdRunning $true

        $operation.SetAutomatic | Should -BeFalse
        $operation.Start | Should -BeFalse
        $operation.Status | Should -Be 'AlreadyPresent'
        $operation.Changed | Should -BeFalse
    }

    It '显式非 Tailscale 地址返回 Invalid 2 且不读取系统状态' {
        $document = Invoke-WindowsAnsibleHostPreparation -TailscaleIPv4 '192.168.1.20'

        $document.Status | Should -Be 'Invalid'
        $document.ExitCode | Should -Be 2
        $document.Results[0].Message | Should -Match 'Tailscale IPv4'
    }

    It '非 Windows 入口仍输出单个可解析 JSON document' -Skip:$IsWindows {
        $output = pwsh -NoProfile -File $script:EntryPath -OutputFormat Json 2>$null
        $document = $output | Out-String | ConvertFrom-Json

        $LASTEXITCODE | Should -Be 10
        $document.Platform | Should -Be 'Windows'
        $document.Status | Should -Be 'Blocked'
        $document.Results.Count | Should -BeGreaterThan 0
    }

    It 'Windows PowerShell 5.1 单文件入口及全部依赖使用 UTF-8 BOM 且 parser 无错误' {
        foreach ($path in @($script:EntryPath, $script:ModulePath, $script:BootstrapModulePath)) {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            @($bytes[0..2]) | Should -Be @(0xEF, 0xBB, 0xBF)
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }

    It '单文件入口保留公开 revision 下载能力' {
        $content = Get-Content -LiteralPath $script:EntryPath -Raw

        $content | Should -Match 'SourceRevision'
        $content | Should -Match 'raw\.githubusercontent\.com/mudssky/powershellScripts'
        $content | Should -Match 'WindowsAnsibleHostPreparation\.psm1'
        $content | Should -Match '\$revisionIsImmutable'
        $content | Should -Match '\$cacheComplete'
        $content | Should -Match 'download-\{0\}'
        $content | Should -Match 'Move-Item.*-Force'
    }

    It '单文件入口和执行模块将可读进度写入 stderr' {
        $entryContent = Get-Content -LiteralPath $script:EntryPath -Raw
        $moduleContent = Get-Content -LiteralPath $script:ModulePath -Raw

        $entryContent | Should -Match '\[Console\]::Error\.WriteLine'
        $entryContent | Should -Match '下载依赖 \{0\}/\{1\}'
        $moduleContent | Should -Match '\[阶段 \{2\}\]'
        $moduleContent | Should -Match '标题为 Operation 的系统进度条属于此步骤'
        $moduleContent | Should -Match '常见耗时 5-20 分钟'
    }
}
