# Nix Package Source Adapter Tests

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'NixAdapter' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
        Import-Module (Join-Path $repoRoot 'scripts/pwsh/misc/package-sources/adapters/NixAdapter.psm1') -Force

        $script:OriginalSystemRoot = [Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT', 'Process')
        $script:OriginalSkipRestart = [Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_SKIP_NIX_RESTART', 'Process')
        $script:OriginalFailRestart = [Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_NIX_RESTART_FAIL', 'Process')
    }
    AfterAll {
        if ($null -eq $script:OriginalSystemRoot) {
            Remove-Item Env:POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT', $script:OriginalSystemRoot, 'Process')
        }
        if ($null -eq $script:OriginalSkipRestart) {
            Remove-Item Env:POWERSHELL_SCRIPTS_SKIP_NIX_RESTART -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_SKIP_NIX_RESTART', $script:OriginalSkipRestart, 'Process')
        }
        if ($null -eq $script:OriginalFailRestart) {
            Remove-Item Env:POWERSHELL_SCRIPTS_NIX_RESTART_FAIL -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_NIX_RESTART_FAIL', $script:OriginalFailRestart, 'Process')
        }
    }

    It 'Merge-NixConfSubstituters 保持官方 fallback 与注释/未知键' {
        $existing = @(
            '# comment keep'
            'extra-experimental-features = nix-command flakes'
            'substituters = https://cache.nixos.org/'
        ) -join "`n"
        $merged = Merge-NixConfSubstituters -ExistingText $existing -MirrorUrls @(
            'https://mirrors.ustc.edu.cn/nix-channels/store'
        ) -TrustedPublicKeys @(
            'cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY='
        )
        $merged | Should -Match '# comment keep'
        $merged | Should -Match 'extra-experimental-features = nix-command flakes'
        $merged | Should -Match 'mirrors.ustc.edu.cn/nix-channels/store'
        $merged | Should -Match 'cache.nixos.org/'
        # USTC 在官方之前
        $ustc = $merged.IndexOf('mirrors.ustc.edu.cn')
        $official = $merged.IndexOf('https://cache.nixos.org/')
        $ustc | Should -BeLessThan $official
        $merged | Should -Not -Match 'require-sigs\s*=\s*false'
        $merged | Should -Not -Match 'trusted-users'
    }

    It '测试系统根下 Apply 写入 .bak 且二次幂等' {
        $root = Join-Path $TestDrive 'nix-root'
        $confDir = Join-Path $root 'etc/nix'
        New-Item -ItemType Directory -Path $confDir -Force | Out-Null
        $confPath = Join-Path $confDir 'nix.conf'
        Set-Content -LiteralPath $confPath -Value "extra-experimental-features = nix-command flakes`n" -Encoding utf8

        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT', $root, 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_SKIP_NIX_RESTART', '1', 'Process')

        $cfg = @{
            adapter             = 'nix'
            scope               = 'system'
            resource            = '/etc/nix/nix.conf'
            mirror_urls         = @('https://mirrors.ustc.edu.cn/nix-channels/store')
            trusted_public_keys = @('cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=')
        }

        $first = Invoke-NixPackageSourceApply -TargetConfig $cfg -TimeoutSeconds 15 -Retry 1
        $first.Changed | Should -BeTrue
        $first.Source | Should -Match 'ustc|cache.nixos.org'
        (Get-Content -LiteralPath $confPath -Raw) | Should -Match 'substituters'
        $backups = @(Get-ChildItem -LiteralPath $confDir -Filter 'nix.conf.*.bak')
        $backups.Count | Should -BeGreaterThan 0

        $second = Invoke-NixPackageSourceApply -TargetConfig $cfg -TimeoutSeconds 15 -Retry 1
        $second.Changed | Should -BeFalse
    }

    It '真实系统路径无 root 时返回 Blocked' -Skip:(-not $IsLinux) {
        Remove-Item Env:POWERSHELL_SCRIPTS_SYSTEM_SOURCE_ROOT -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable('POWERSHELL_SCRIPTS_SKIP_NIX_RESTART', '1', 'Process')
        $cfg = @{
            adapter     = 'nix'
            scope       = 'system'
            resource    = '/etc/nix/nix.conf'
            mirror_urls = @('https://mirrors.ustc.edu.cn/nix-channels/store')
        }
        # 非 root 用户应被拒绝
        $uid = & id -u
        if ($uid -eq '0') {
            Set-ItResult -Skipped -Because '当前为 root，无法验证非 root Blocked 分支'
            return
        }
        { Invoke-NixPackageSourceApply -TargetConfig $cfg -TimeoutSeconds 3 -Retry 0 } | Should -Throw '*root*'
    }
}
