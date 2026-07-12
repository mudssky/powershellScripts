BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:RepoRoot 'windows/bootstrap/WindowsRemotePsRemoting.psm1'
    $script:EntryPath = Join-Path $script:RepoRoot 'windows/bootstrap/Enable-WindowsRemotePsRemoting.ps1'
    Import-Module $script:ModulePath -Force

    function Get-WindowsRemotePlanAction {
        <#
        .SYNOPSIS
            从 PSRP plan 读取指定动作。

        .PARAMETER Plan
            New-WindowsRemotePsRemotingPlan 返回的 plan。

        .PARAMETER Name
            动作资源名。

        .OUTPUTS
            PSCustomObject。匹配的单个动作。
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [object]$Plan,

            [Parameter(Mandatory)]
            [string]$Name
        )

        return @($Plan.Actions | Where-Object Name -eq $Name) | Select-Object -First 1
    }

    function Invoke-WindowsRemoteTestProcess {
        <#
        .SYNOPSIS
            在独立 pwsh 进程执行远程 PSRP 入口。

        .PARAMETER ArgumentList
            传给入口脚本的参数数组。

        .OUTPUTS
            PSCustomObject。包含 ExitCode、Stdout 和 Stderr。
        #>
        [CmdletBinding()]
        param(
            [string[]]$ArgumentList
        )

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $script:EntryPath) + @($ArgumentList)) {
            $startInfo.ArgumentList.Add([string]$argument)
        }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
    }
}

Describe 'Windows Tailscale IPv4 选择' {
    It '接受 CGNAT 地址并拒绝 LAN、loopback 和 IPv6' {
        Test-WindowsTailscaleIPv4 -IPAddress '100.64.0.1' | Should -BeTrue
        Test-WindowsTailscaleIPv4 -IPAddress '100.127.255.254' | Should -BeTrue
        Test-WindowsTailscaleIPv4 -IPAddress '192.168.1.10' | Should -BeFalse
        Test-WindowsTailscaleIPv4 -IPAddress '127.0.0.1' | Should -BeFalse
        Test-WindowsTailscaleIPv4 -IPAddress 'fd7a:115c:a1e0::1' | Should -BeFalse
    }

    It '从重复候选中返回唯一地址' {
        Select-WindowsTailscaleIPv4 -Candidate @('100.70.1.2', '100.70.1.2', '192.168.1.10') |
            Should -Be '100.70.1.2'
    }

    It '多个有效地址时要求显式指定' {
        { Select-WindowsTailscaleIPv4 -Candidate @('100.70.1.2', '100.70.1.3') } |
            Should -Throw '*多个 Tailscale IPv4*'
    }
}

Describe 'Windows PSRP 证书与 listener 计划' {
    It '复用有效期超过 30 天的最新托管证书' {
        $now = [datetime]'2026-07-12T00:00:00Z'
        $selected = Select-WindowsRemotePsRemotingCertificate -Now $now -Certificate @(
            [pscustomobject]@{ Subject = 'CN=unmanaged'; HasPrivateKey = $true; NotBefore = $now.AddDays(-1); NotAfter = $now.AddYears(5); Thumbprint = 'UNMANAGED' },
            [pscustomobject]@{ Subject = 'CN=powershellScripts-PSRP-old'; HasPrivateKey = $true; NotBefore = $now.AddYears(-1); NotAfter = $now.AddDays(10); Thumbprint = 'OLD' },
            [pscustomobject]@{ Subject = 'CN=powershellScripts-PSRP-current'; HasPrivateKey = $true; NotBefore = $now.AddDays(-1); NotAfter = $now.AddYears(3); Thumbprint = 'CURRENT' }
        )
        $selected.Thumbprint | Should -Be 'CURRENT'
    }

    It '把 WSMan keys 转换为精确 address、transport 和 port' {
        $listener = ConvertFrom-WindowsWsManListener -Listener ([pscustomobject]@{
                Keys                  = @('Transport=HTTPS', 'Address=100.70.1.2', 'Port=5986')
                CertificateThumbprint = 'ABC'
                PSPath                = 'WSMan:\localhost\Listener\Listener_1'
            })
        $listener.Address | Should -Be '100.70.1.2'
        $listener.Transport | Should -Be 'HTTPS'
        $listener.Port | Should -Be 5986
        $listener.CertificateThumbprint | Should -Be 'ABC'
    }

    It '从 WSMan provider 子项读取 port 和证书指纹' {
        InModuleScope WindowsRemotePsRemoting {
            Mock Get-Item {
                if ($LiteralPath -like '*\Port') {
                    return [pscustomobject]@{ Value = 5986 }
                }
                return [pscustomobject]@{ Value = 'FROM-CHILD' }
            }
            $listener = ConvertFrom-WindowsWsManListener -Listener ([pscustomobject]@{
                    Keys   = @('Transport=HTTPS', 'Address=100.70.1.2')
                    PSPath = 'WSMan:\localhost\Listener\Listener_1'
                })
            $listener.Port | Should -Be 5986
            $listener.CertificateThumbprint | Should -Be 'FROM-CHILD'
        }
    }

    It '拒绝 wildcard 或其他接口 listener' {
        Test-WindowsRemotePsRemotingBinding -IPAddress '100.70.1.2' -Listener @(
            [pscustomobject]@{ Transport = 'HTTPS'; Address = '100.70.1.2'; Port = 5986 },
            [pscustomobject]@{ Transport = 'HTTPS'; Address = '*'; Port = 5986 }
        ) | Should -BeFalse
    }

    It '缺失状态生成证书、listener 和 scoped firewall 创建计划' {
        $plan = New-WindowsRemotePsRemotingPlan -IPAddress '100.70.1.2' -FirewallEnabled
        (Get-WindowsRemotePlanAction -Plan $plan -Name Certificate).Action | Should -Be 'Create'
        (Get-WindowsRemotePlanAction -Plan $plan -Name HttpsListener).Action | Should -Be 'Create'
        (Get-WindowsRemotePlanAction -Plan $plan -Name FirewallRule).Action | Should -Be 'Ensure'
        (Get-WindowsRemotePlanAction -Plan $plan -Name FirewallRule).Message | Should -Match '100.64.0.0/10'
    }

    It '已满足状态生成幂等计划' {
        $plan = New-WindowsRemotePsRemotingPlan -IPAddress '100.70.1.2' `
            -CertificateReusable -ManagedCertificateExists -ListenerState Matched `
            -FirewallEnabled -FirewallRuleExists -FirewallRuleMatches
        (Get-WindowsRemotePlanAction -Plan $plan -Name Certificate).Action | Should -Be 'Reuse'
        (Get-WindowsRemotePlanAction -Plan $plan -Name HttpsListener).Action | Should -Be 'AlreadyPresent'
        (Get-WindowsRemotePlanAction -Plan $plan -Name FirewallRule).Action | Should -Be 'AlreadyPresent'
    }

    It '防火墙关闭时保持全局状态并只安排验证' {
        $plan = New-WindowsRemotePsRemotingPlan -IPAddress '100.70.1.2'
        (Get-WindowsRemotePlanAction -Plan $plan -Name FirewallRule).Action | Should -Be 'Skip'
        (Get-WindowsRemotePlanAction -Plan $plan -Name FirewallRule).Message | Should -Match '保持全局状态'
    }

    It '非托管 listener 冲突返回 Blocked 10' {
        $plan = New-WindowsRemotePsRemotingPlan -IPAddress '100.70.1.2' -ListenerState Conflict
        $plan.Status | Should -Be 'Blocked'
        $plan.ExitCode | Should -Be 10
        (Get-WindowsRemotePlanAction -Plan $plan -Name HttpsListener).Action | Should -Be 'Blocked'
    }

    It 'rollback 只删除托管 listener、rule 和证书' {
        $plan = New-WindowsRemotePsRemotingPlan -IPAddress '100.70.1.2' -Rollback `
            -ListenerState Matched -ManagedCertificateExists -FirewallRuleExists
        $plan.Operation | Should -Be 'Rollback'
        (Get-WindowsRemotePlanAction -Plan $plan -Name HttpsListener).Action | Should -Be 'Remove'
        (Get-WindowsRemotePlanAction -Plan $plan -Name FirewallRule).Action | Should -Be 'Remove'
        (Get-WindowsRemotePlanAction -Plan $plan -Name Certificate).Action | Should -Be 'Remove'
        ($plan.Actions.Message -join ' ') | Should -Match 'OpenSSH 未修改'
    }

    It '防火墙过滤器只接受单一精确地址和端口' {
        InModuleScope WindowsRemotePsRemoting {
            $rule = [pscustomobject]@{ Enabled = $true; Direction = 'Inbound'; Action = 'Allow' }
            $portFilter = [pscustomobject]@{ Protocol = 'TCP'; LocalPort = @('5986') }
            $addressFilter = [pscustomobject]@{
                LocalAddress  = @('100.70.1.2')
                RemoteAddress = @('100.64.0.0/10')
            }
            Test-WindowsRemotePsRemotingFirewallRule -Rule $rule -PortFilter $portFilter `
                -AddressFilter $addressFilter -IPAddress '100.70.1.2' | Should -BeTrue
            $addressFilter.LocalAddress = @('100.70.1.2', '192.168.1.10')
            Test-WindowsRemotePsRemotingFirewallRule -Rule $rule -PortFilter $portFilter `
                -AddressFilter $addressFilter -IPAddress '100.70.1.2' | Should -BeFalse
        }
    }
}

Describe 'Windows PSRP 入口合同' {
    It 'Windows 非管理员真实执行在读取系统状态前返回 Blocked 10' {
        InModuleScope WindowsRemotePsRemoting {
            Mock Test-WindowsRemotePsRemotingWindowsHost { $true }
            Mock Test-WindowsBootstrapAdministrator { $false }
            Mock Get-WindowsRemotePsRemotingState { throw '不应读取系统状态' }
            $document = Invoke-WindowsRemotePsRemoting -TailscaleIPv4 '100.70.1.2'
            $document.Status | Should -Be 'Blocked'
            $document.ExitCode | Should -Be 10
            $document.Results[0].Name | Should -Be 'Administrator'
            Should -Invoke Get-WindowsRemotePsRemotingState -Times 0 -Exactly
        }
    }

    It '非 Windows 也能用显式 IP 生成单文档 WhatIf JSON' `
        -Skip:([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $result = Invoke-WindowsRemoteTestProcess -ArgumentList @(
            '-TailscaleIPv4', '100.70.1.2',
            '-WhatIf',
            '-OutputFormat', 'Json'
        )
        $result.ExitCode | Should -Be 0
        $document = $result.Stdout | ConvertFrom-Json
        $document.Status | Should -Be 'Preview'
        $document.TailscaleIPv4 | Should -Be '100.70.1.2'
        $document.OpenSshUnchanged | Should -BeTrue
        $result.Stderr | Should -BeNullOrEmpty
    }

    It 'Windows bootstrap 文件均可由当前 parser 解析' {
        $errors = [System.Collections.Generic.List[object]]::new()
        foreach ($file in @($script:ModulePath, $script:EntryPath)) {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
            foreach ($parseError in @($parseErrors)) {
                $errors.Add($parseError)
            }
        }
        $errors.Count | Should -Be 0
    }

    It 'Windows PowerShell 5.1 入口和模块使用 UTF-8 BOM' {
        foreach ($file in @($script:ModulePath, $script:EntryPath)) {
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }
    }

    It 'Windows PowerShell 5.1 parser 可加载模块和入口' `
        -Skip:($null -eq (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $pathLiteral = @(@($script:ModulePath, $script:EntryPath) | ForEach-Object {
                "'{0}'" -f ([string]$_).Replace("'", "''")
            }) -join ', '
        $command = @"
`$errors = [System.Collections.Generic.List[object]]::new()
foreach (`$file in @($pathLiteral)) {
    `$tokens = `$null
    `$parseErrors = `$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(`$file, [ref]`$tokens, [ref]`$parseErrors)
    foreach (`$parseError in @(`$parseErrors)) {
        `$errors.Add(`$parseError)
    }
}
if (`$errors.Count -gt 0) {
    `$errors | ForEach-Object { [Console]::Error.WriteLine(`$_.Message) }
    exit 1
}
"@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        & powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedCommand
        $LASTEXITCODE | Should -Be 0
    }
}
