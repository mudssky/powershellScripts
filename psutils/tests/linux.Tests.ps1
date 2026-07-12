BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'linux.psm1') -Force
}

Describe 'Set-SSHKeyAuth 运行时安全边界' {
    BeforeEach {
        $global:CapturedSshKeygenArgs = $null
        $global:LASTEXITCODE = 0

        Mock -ModuleName linux Get-Command { [PSCustomObject]@{ Name = $Name } } -ParameterFilter {
            $Name -in @('ssh-keygen', 'ssh')
        }
        Mock -ModuleName linux Test-Connection { $true }
        Mock -ModuleName linux Test-Path { $false }
        Mock -ModuleName linux New-Item { }
        Mock -ModuleName linux Get-Content { 'ssh-rsa test' }
        Mock -ModuleName linux Write-Host { }
        Mock -ModuleName linux ssh-keygen {
            $global:CapturedSshKeygenArgs = @($args)
            $global:LASTEXITCODE = 0
        }
        Mock -ModuleName linux ssh {
            $global:LASTEXITCODE = 0
        }
    }

    AfterEach {
        Remove-Variable -Name CapturedSshKeygenArgs -Scope Global -ErrorAction SilentlyContinue
    }

    It '默认使用 HOME 下的 .ssh 并传递空口令' {
        Set-SSHKeyAuth -RemoteUser 'tester' -RemoteHost 'example.test' | Should -BeTrue

        Should -Invoke New-Item -ModuleName linux -Times 1 -Exactly -ParameterFilter {
            $Path -eq (Join-Path $HOME '.ssh')
        }
        $global:CapturedSshKeygenArgs | Should -Contain '-N'
        $passphraseIndex = [Array]::IndexOf($global:CapturedSshKeygenArgs, '-N') + 1
        $global:CapturedSshKeygenArgs[$passphraseIndex] | Should -Be ''
    }

    It '拒绝把非空口令放入原生进程参数且错误不回显口令' {
        $secret = 'do-not-log-this'
        $errors = @()

        $result = Set-SSHKeyAuth -RemoteUser 'tester' -RemoteHost 'example.test' -Passphrase $secret -ErrorAction SilentlyContinue -ErrorVariable errors

        $result | Should -BeFalse
        ($errors | Out-String) | Should -Not -Match ([regex]::Escape($secret))
        Should -Invoke ssh-keygen -ModuleName linux -Times 0 -Exactly
    }

    It '交互口令模式不会传递 -N 参数' {
        Set-SSHKeyAuth -RemoteUser 'tester' -RemoteHost 'example.test' -PromptForPassphrase | Should -BeTrue

        $global:CapturedSshKeygenArgs | Should -Not -Contain '-N'
    }

    It '拒绝可能改变 ssh 参数边界的用户名' {
        Set-SSHKeyAuth -RemoteUser '-oProxyCommand' -RemoteHost 'example.test' -ErrorAction SilentlyContinue | Should -BeFalse

        Should -Invoke ssh-keygen -ModuleName linux -Times 0 -Exactly
    }

    It 'WhatIf 不执行网络探测或原生命令' {
        Set-SSHKeyAuth -RemoteUser 'tester' -RemoteHost 'example.test' -WhatIf | Out-Null

        Should -Invoke Test-Connection -ModuleName linux -Times 0 -Exactly
        Should -Invoke ssh-keygen -ModuleName linux -Times 0 -Exactly
        Should -Invoke ssh -ModuleName linux -Times 0 -Exactly
    }
}
