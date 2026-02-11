param()

Describe 'Unix Profile 性能基准' -Tag 'profile', 'performance', 'unix', 'Slow' {
    BeforeAll {
        $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:ProfilePath = Join-Path $RepoRoot 'profile' 'profile_unix.ps1'
        if (-not (Test-Path $script:ProfilePath)) {
            throw "Profile 文件不存在: $script:ProfilePath"
        }
    }

    It '默认模式加载时间' {
        if (-not ($IsLinux -or $IsMacOS)) { Set-ItResult -Skipped -Because '仅在 Linux/macOS 运行'; return }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        . $script:ProfilePath
        $sw.Stop()
        $ms = $sw.ElapsedMilliseconds
        Write-Host ("[Unix Default] Profile 加载耗时: {0} ms" -f $ms) -ForegroundColor Cyan
        $ms | Should -BeGreaterThan 0
        $ms | Should -BeLessThan 10000
    }

    It 'Minimal 模式加载时间' {
        if (-not ($IsLinux -or $IsMacOS)) { Set-ItResult -Skipped -Because '仅在 Linux/macOS 运行'; return }
        $env:POWERSHELL_PROFILE_MINIMAL = 1
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        . $script:ProfilePath
        $sw.Stop()
        Remove-Item Env:\POWERSHELL_PROFILE_MINIMAL -ErrorAction SilentlyContinue
        $ms = $sw.ElapsedMilliseconds
        Write-Host ("[Unix Minimal] Profile 加载耗时: {0} ms" -f $ms) -ForegroundColor Cyan
        $ms | Should -BeGreaterThan 0
        $ms | Should -BeLessThan 10000
    }
}
