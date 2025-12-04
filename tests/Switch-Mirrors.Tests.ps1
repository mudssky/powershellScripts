Import-Module Pester -ErrorAction SilentlyContinue

Describe 'Switch-Mirrors.ps1' {
    It '测试镜像探活应返回 Success 为 true（官方仓库）' {
        $scriptPath = Join-Path $PSScriptRoot '..' 'Switch-Mirrors.ps1'
        . $scriptPath
        $r = Test-MirrorUrl -Url 'https://registry-1.docker.io' -TimeoutSec 5 -Retry 0
        $r.Success | Should -BeTrue
        ($r.StatusCode -in 200,401) | Should -BeTrue
    }

    It '测试不可达地址返回 Success 为 false' {
        $scriptPath = Join-Path $PSScriptRoot '..' 'Switch-Mirrors.ps1'
        . $scriptPath
        $r = Test-MirrorUrl -Url 'https://invalid.invalid-domain.example' -TimeoutSec 2 -Retry 0
        $r.Success | Should -BeFalse
    }

    It 'DryRun 写入不应实际修改文件（仅输出）' {
        $scriptPath = Join-Path $PSScriptRoot '..' 'Switch-Mirrors.ps1'
        $daemon = if ($IsLinux) { '/etc/docker/daemon.json' } elseif ($IsWindows) { Join-Path $env:ProgramData 'Docker\config\daemon.json' } else { Join-Path $HOME '.docker/daemon.json' }
        $before = if (Test-Path -LiteralPath $daemon) { Get-Content -LiteralPath $daemon -Raw } else { '' }
        pwsh -NoLogo -NoProfile -File $scriptPath -Target docker -MirrorUrls 'https://registry-1.docker.io' -DryRun | Out-Null
        $after = if (Test-Path -LiteralPath $daemon) { Get-Content -LiteralPath $daemon -Raw } else { '' }
        $after | Should -BeExactly $before
    }
}

