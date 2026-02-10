Set-StrictMode -Version Latest

$pesterModule = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pesterModule -or $pesterModule.Version.Major -lt 5) {
    throw 'Pester 5.x is required to run this test. Install-Module Pester -Scope CurrentUser -Force'
}
Import-Module Pester -MinimumVersion 5.0 -Force

$profileRootDir = Join-Path $PSScriptRoot '..' 'profile'
. (Join-Path $profileRootDir 'core/mode.ps1')
. (Join-Path $profileRootDir 'core/encoding.ps1')
. (Join-Path $profileRootDir 'features/environment.ps1')

Describe 'Profile mode decision priority' {
    BeforeAll {
        $script:ModeEnvNames = @(
            'POWERSHELL_PROFILE_FULL',
            'POWERSHELL_PROFILE_MODE',
            'POWERSHELL_PROFILE_ULTRA_MINIMAL',
            'POWERSHELL_PROFILE_MINIMAL',
            'POWERSHELL_PROFILE_FAST',
            'POWERSHELL_PROFILE_LIGHT',
            'CODEX_THREAD_ID',
            'CODEX_SANDBOX_NETWORK_DISABLED'
        )

        $script:OriginalModeEnv = @{}
        foreach ($envName in $script:ModeEnvNames) {
            $script:OriginalModeEnv[$envName] = [Environment]::GetEnvironmentVariable($envName, 'Process')
        }
    }

    BeforeEach {
        foreach ($envName in $script:ModeEnvNames) {
            Remove-Item "Env:$envName" -ErrorAction SilentlyContinue
        }
    }

    AfterAll {
        foreach ($envName in $script:ModeEnvNames) {
            $value = $script:OriginalModeEnv[$envName]
            if ($null -eq $value) {
                Remove-Item "Env:$envName" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item "Env:$envName" -Value $value
            }
        }
    }

    It 'POWERSHELL_PROFILE_FULL should override MODE and ULTRA_MINIMAL' {
        $env:POWERSHELL_PROFILE_FULL = '1'
        $env:POWERSHELL_PROFILE_MODE = 'ultra'
        $env:POWERSHELL_PROFILE_ULTRA_MINIMAL = '1'

        $decision = Get-ProfileModeDecision
        $decision.Mode | Should -Be 'Full'
        $decision.Reason | Should -Be 'explicit_full'
    }

    It 'POWERSHELL_PROFILE_MODE=minimal should resolve Minimal' {
        $env:POWERSHELL_PROFILE_MODE = 'minimal'

        $decision = Get-ProfileModeDecision
        $decision.Mode | Should -Be 'Minimal'
        $decision.Reason | Should -Be 'explicit_mode_minimal'
    }

    It 'CODEX_THREAD_ID should auto-resolve UltraMinimal when no explicit switches' {
        $env:CODEX_THREAD_ID = 'thread-123'

        $decision = Get-ProfileModeDecision
        $decision.Mode | Should -Be 'UltraMinimal'
        $decision.Source | Should -Be 'auto'
        $decision.Reason | Should -Be 'auto_codex_thread'
    }

    It 'should default to Full without any markers' {
        $decision = Get-ProfileModeDecision
        $decision.Mode | Should -Be 'Full'
        $decision.Reason | Should -Be 'default_full'
    }
}

Describe 'Initialize-Environment UltraMinimal path' {
    BeforeEach {
        $script:ProfileRoot = (Resolve-Path $profileRootDir).Path
        $script:ProfileMode = 'UltraMinimal'
        $script:UseUltraMinimalProfile = $true
        $script:UseMinimalProfile = $false
        $script:profileLoadStartTime = Get-Date
        $script:ProfileModeDecision = [PSCustomObject]@{
            Mode      = 'UltraMinimal'
            Source    = 'auto'
            Reason    = 'auto_codex_thread'
            Markers   = @('CODEX_THREAD_ID')
            ElapsedMs = 0
            V2        = $null
        }

        $script:proxyInvoked = $false
        $script:pathSyncInvoked = $false
        $script:utf8Invoked = $false

        function global:Set-Proxy {
            param([string]$Command)
            $script:proxyInvoked = $true
        }

        function global:Sync-PathFromBash {
            param(
                [int]$CacheSeconds,
                [switch]$ErrorAction
            )
            $script:pathSyncInvoked = $true
            return $null
        }

        function global:Set-ProfileUtf8Encoding {
            $script:utf8Invoked = $true
        }
    }

    AfterEach {
        Remove-Item Function:\Set-Proxy -ErrorAction SilentlyContinue
        Remove-Item Function:\Sync-PathFromBash -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-ProfileUtf8Encoding -ErrorAction SilentlyContinue
    }

    It 'should keep minimal init and skip proxy/path sync in UltraMinimal mode' {
        Initialize-Environment

        $env:POWERSHELL_SCRIPTS_ROOT | Should -Be (Split-Path -Parent $script:ProfileRoot)
        $script:utf8Invoked | Should -Be $true
        $script:proxyInvoked | Should -Be $false
        $script:pathSyncInvoked | Should -Be $false
    }
}
