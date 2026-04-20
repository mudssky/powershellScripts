Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1'
    $script:OriginalSkipFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN = '1'

    . $script:ScriptPath
}

AfterAll {
    if ($null -eq $script:OriginalSkipFlag) {
        Remove-Item Env:\PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN', $script:OriginalSkipFlag, 'Process')
    }
}

Describe 'Get-TailscaleDerpManagedPaths' {
    It 'builds a Linux/macOS config path under the user home directory' {
        $paths = Get-TailscaleDerpManagedPaths -Platform 'Linux' -HomeDirectory '/home/demo'

        $paths.DerpJsonPath | Should -Be '/home/demo/.config/powershell-scripts/tailscale/derp.json'
        $paths.StatePath | Should -Be '/home/demo/.config/powershell-scripts/tailscale/derp-state.json'
    }

    It 'builds a Windows config path under APPDATA' {
        $paths = Get-TailscaleDerpManagedPaths -Platform 'Windows' -AppDataDirectory 'C:\Users\Demo\AppData\Roaming'

        $paths.DerpJsonPath | Should -Be 'C:\Users\Demo\AppData\Roaming\powershell-scripts\tailscale\derp.json'
        $paths.StatePath | Should -Be 'C:\Users\Demo\AppData\Roaming\powershell-scripts\tailscale\derp-state.json'
    }
}

Describe 'Convert-TailscalePathToFileUri' {
    It 'converts a Windows path to a file URI' {
        Convert-TailscalePathToFileUri -Path 'C:\Users\Demo\AppData\Roaming\powershell-scripts\tailscale\derp.json' |
            Should -Be 'file:///C:/Users/Demo/AppData/Roaming/powershell-scripts/tailscale/derp.json'
    }

    It 'converts a POSIX path to a file URI' {
        Convert-TailscalePathToFileUri -Path '/home/demo/.config/powershell-scripts/tailscale/derp.json' |
            Should -Be 'file:///home/demo/.config/powershell-scripts/tailscale/derp.json'
    }
}

Describe 'Get-TailscaleCliCommandSpec' {
    It 'uses the standalone macOS app binary in CLI mode when the resolved command is a symlink to it' {
        $spec = Get-TailscaleCliCommandSpec `
            -IsMacPlatform $true `
            -MacAppPath '/Applications/Tailscale.app/Contents/MacOS/Tailscale' `
            -MacAppExists $true `
            -ResolvedCliPath '/usr/local/bin/tailscale' `
            -ResolvedCliLinkTarget '/Applications/Tailscale.app/Contents/MacOS/Tailscale'

        $spec.CommandPath | Should -Be '/Applications/Tailscale.app/Contents/MacOS/Tailscale'
        $spec.Environment['TAILSCALE_BE_CLI'] | Should -Be '1'
    }

    It 'keeps the resolved command on macOS when it is not the crashing app symlink path' {
        $spec = Get-TailscaleCliCommandSpec `
            -IsMacPlatform $true `
            -MacAppPath '/Applications/Tailscale.app/Contents/MacOS/Tailscale' `
            -MacAppExists $true `
            -ResolvedCliPath '/opt/homebrew/bin/tailscale' `
            -ResolvedCliLinkTarget ''

        $spec.CommandPath | Should -Be '/opt/homebrew/bin/tailscale'
        $spec.Environment.Count | Should -Be 0
    }
}

Describe 'New-TailscaleDerpMapJson' {
    It 'builds the expected single-region DERP map document' {
        $json = New-TailscaleDerpMapJson `
            -ServerIp '203.0.113.10' `
            -RegionId 900 `
            -RegionCode 'cn-custom' `
            -NodeName 'cn-node' `
            -DerpPort 8443 `
            -StunPort 3478

        $doc = $json | ConvertFrom-Json -Depth 10
        $node = $doc.Regions.PSObject.Properties['900'].Value.Nodes[0]

        $node.HostName | Should -Be '203.0.113.10'
        $node.DERPPort | Should -Be 8443
        $node.STUNPort | Should -Be 3478
        $node.InsecureForTests | Should -BeTrue
    }
}

Describe 'Convert-TailscalePrefsToRestoreArgs' {
    It 'maps supported non-default prefs to a stable tailscale up argument list' {
        $prefs = [pscustomobject]@{
            ControlURL             = 'https://controlplane.tailscale.com'
            CorpDNS                = $true
            RouteAll               = $true
            ExitNodeIP             = '100.64.0.1'
            ExitNodeAllowLANAccess = $true
            RunSSH                 = $true
            ShieldsUp              = $false
            Hostname               = 'demo-host'
            AdvertiseRoutes        = @('10.0.0.0/24')
            AdvertiseTags          = @('tag:lab')
            NoSNAT                 = $true
        }

        $args = Convert-TailscalePrefsToRestoreArgs -Prefs $prefs

        $args | Should -Contain '--accept-routes=true'
        $args | Should -Contain '--exit-node=100.64.0.1'
        $args | Should -Contain '--ssh=true'
        $args | Should -Contain '--hostname=demo-host'
        $args | Should -Contain '--snat-subnet-routes=false'
    }

    It 'omits unsupported flags when the current setting is already at its default value' {
        $prefs = [pscustomobject]@{
            ControlURL             = 'https://controlplane.tailscale.com'
            CorpDNS                = $true
            RouteAll               = $true
            ExitNodeIP             = ''
            ExitNodeAllowLANAccess = $false
            RunSSH                 = $false
            ShieldsUp              = $false
            Hostname               = ''
            AdvertiseRoutes        = @()
            AdvertiseTags          = @()
            NoSNAT                 = $false
        }

        $args = Convert-TailscalePrefsToRestoreArgs `
            -Prefs $prefs `
            -SupportedUpFlags @(
                '--login-server',
                '--accept-dns',
                '--accept-routes',
                '--exit-node-allow-lan-access',
                '--ssh',
                '--shields-up'
            )

        $args | Should -Not -Contain '--snat-subnet-routes=true'
        $args | Should -Contain '--accept-routes=true'
    }

    It 'throws when an unsupported flag is required to preserve a non-default setting' {
        $prefs = [pscustomobject]@{
            ControlURL             = 'https://controlplane.tailscale.com'
            CorpDNS                = $true
            RouteAll               = $false
            ExitNodeIP             = ''
            ExitNodeAllowLANAccess = $false
            RunSSH                 = $false
            ShieldsUp              = $false
            Hostname               = ''
            AdvertiseRoutes        = @()
            AdvertiseTags          = @()
            NoSNAT                 = $true
        }

        {
            Convert-TailscalePrefsToRestoreArgs `
                -Prefs $prefs `
                -SupportedUpFlags @(
                    '--login-server',
                    '--accept-dns',
                    '--accept-routes',
                    '--exit-node-allow-lan-access',
                    '--ssh',
                    '--shields-up'
                )
        } | Should -Throw '*snat-subnet-routes*当前 CLI/平台不支持*'
    }

    It 'throws when an unsupported non-default preference would be lost on restore' {
        $prefs = [pscustomobject]@{
            ControlURL             = 'https://controlplane.tailscale.com'
            RunWebClient           = $true
            CorpDNS                = $true
            RouteAll               = $false
            ExitNodeIP             = ''
            NoSNAT                 = $false
            AdvertiseRoutes        = $null
            AdvertiseTags          = $null
            ExitNodeAllowLANAccess = $false
            RunSSH                 = $false
            ShieldsUp              = $false
            Hostname               = ''
        }

        {
            Convert-TailscalePrefsToRestoreArgs -Prefs $prefs
        } | Should -Throw '*RunWebClient*'
    }
}

Describe 'Get-TailscaleUpSupportedFlags' {
    It 'parses supported flag names from tailscale up help output even when pwsh injects stderr wrapper lines' {
        Mock -CommandName Invoke-TailscaleCli -MockWith {
            return [pscustomobject]@{
                ExitCode    = 0
                CommandPath = '/Applications/Tailscale.app/Contents/MacOS/Tailscale'
                Output      = @(
                    'Connect to Tailscale, logging in if needed'
                    'System.Management.Automation.RemoteException'
                    'FLAGS'
                    '  --accept-dns, --accept-dns=false'
                    '  --accept-routes, --accept-routes=false'
                    'System.Management.Automation.RemoteException'
                    '  --login-server value'
                )
            }
        }

        $flags = Get-TailscaleUpSupportedFlags

        $flags | Should -Contain '--accept-dns'
        $flags | Should -Contain '--accept-routes'
        $flags | Should -Contain '--login-server'
    }
}

Describe 'Save-TailscaleDerpState / Read-TailscaleDerpState' {
    It 'round-trips restore arguments and metadata through the managed state file' {
        $statePath = Join-Path $TestDrive 'derp-state.json'
        $state = [pscustomobject]@{
            AppliedAt    = '2026-04-20T09:00:00Z'
            ServerIp     = '203.0.113.10'
            DerpJsonPath = '/tmp/derp.json'
            DerpMapUri   = 'file:///tmp/derp.json'
            RestoreArgs  = @('--accept-routes=true', '--ssh=true')
            CliVersion   = '1.96.4'
        }

        Save-TailscaleDerpState -Path $statePath -State $state
        $loaded = Read-TailscaleDerpState -Path $statePath

        $loaded.ServerIp | Should -Be '203.0.113.10'
        $loaded.RestoreArgs | Should -Be @('--accept-routes=true', '--ssh=true')
    }
}

Describe 'Get-TailscalePrefsSnapshot' {
    It 'parses JSON returned by the shared tailscale invocation helper' {
        Mock -CommandName Invoke-TailscaleCli -MockWith {
            return [pscustomobject]@{
                ExitCode    = 0
                CommandPath = '/Applications/Tailscale.app/Contents/MacOS/Tailscale'
                Output      = @(
                    '# doing request GET http://local-tailscaled.sock/localapi/v0/prefs'
                    '{"ControlURL":"https://controlplane.tailscale.com","CorpDNS":true}'
                )
            }
        }

        $prefs = Get-TailscalePrefsSnapshot

        $prefs.ControlURL | Should -Be 'https://controlplane.tailscale.com'
        $prefs.CorpDNS | Should -BeTrue
    }

    It 'throws a clear error when the CLI returns non-JSON crash text instead of prefs JSON' {
        Mock -CommandName Invoke-TailscaleCli -MockWith {
            return [pscustomobject]@{
                ExitCode    = 1
                CommandPath = '/usr/local/bin/tailscale'
                Output      = @(
                    'Tailscale/BundleIdentifiers.swift:41: Fatal error: The current bundleIdentifier is unknown to the registry'
                )
            }
        }

        {
            Get-TailscalePrefsSnapshot
        } | Should -Throw '*未返回 JSON*BundleIdentifiers.swift*'
    }
}

Describe 'Invoke-TailscaleDerpApply' {
    It 'builds a tailscale up command from restore args plus DERP flags' {
        Mock -CommandName Invoke-TailscaleCli -MockWith {
            param([string[]]$Arguments)

            return [pscustomobject]@{
                ExitCode  = 0
                StdOut    = ''
                StdErr    = ''
                Arguments = $Arguments
            }
        }

        $result = Invoke-TailscaleDerpApply `
            -RestoreArgs @('--accept-routes=true', '--ssh=true') `
            -DerpMapUri 'file:///tmp/derp.json'

        $result.Arguments | Should -Be @(
            'up',
            '--accept-routes=true',
            '--ssh=true',
            '--derp-map-url=file:///tmp/derp.json',
            '--tls-skip-verify'
        )
    }

    It 'rewrites unknown-flag failures into a clear compatibility message' {
        Mock -CommandName Invoke-TailscaleCli -MockWith {
            throw 'unknown flag: --derp-map-url'
        }

        {
            Invoke-TailscaleDerpApply `
                -RestoreArgs @('--accept-routes=true') `
                -DerpMapUri 'file:///tmp/derp.json'
        } | Should -Throw '*当前 Tailscale CLI 不支持自定义 DERP flag*'
    }
}

Describe 'Invoke-TailscaleDerpReset' {
    It 'replays restore args without DERP-specific flags' {
        Mock -CommandName Invoke-TailscaleCli -MockWith {
            param([string[]]$Arguments)

            return [pscustomobject]@{
                ExitCode  = 0
                Arguments = $Arguments
            }
        }

        $result = Invoke-TailscaleDerpReset -RestoreArgs @('--accept-routes=true', '--ssh=true')
        $result.Arguments | Should -Be @('up', '--accept-routes=true', '--ssh=true')
    }

    It 'does not delete managed files when the restore command fails' {
        $statePath = Join-Path $TestDrive 'derp-state.json'
        $derpJsonPath = Join-Path $TestDrive 'derp.json'
        $state = [pscustomobject]@{
            RestoreArgs  = @('--accept-routes=true')
            DerpJsonPath = $derpJsonPath
        }

        Save-TailscaleDerpState -Path $statePath -State $state
        Set-Content -LiteralPath $derpJsonPath -Value '{}'

        Mock -CommandName Invoke-TailscaleCli -MockWith {
            throw 'restore failed'
        }

        {
            Invoke-SetTailscaleDerpCommand -Reset -ManagedStatePath $statePath -ManagedDerpJsonPath $derpJsonPath
        } | Should -Throw '*restore failed*'

        Test-Path -LiteralPath $statePath | Should -BeTrue
        Test-Path -LiteralPath $derpJsonPath | Should -BeTrue
    }
}

Describe 'Test-TailscaleDerpApplyPreconditions' {
    It 'rejects apply when an active managed state file already exists' {
        $statePath = Join-Path $TestDrive 'derp-state.json'
        Set-Content -LiteralPath $statePath -Value '{}'

        {
            Test-TailscaleDerpApplyPreconditions -StatePath $statePath
        } | Should -Throw '*先执行 -Reset*'
    }
}
