$macOSFontCasks = @(
    'font-jetbrains-mono-nerd-font',
    'font-fira-code-nerd-font',
    'font-symbols-only-nerd-font'
)

if ($IsMacOS) {
    if (-not (Get-Command brew -ErrorAction SilentlyContinue)) {
        throw '未找到 Homebrew，无法安装 macOS 字体。请先安装 brew。'
    }

    foreach ($fontCask in $macOSFontCasks) {
        # 字体 cask 不提供 CLI，必须通过 brew cask 列表判断是否已安装，避免重复安装报错。
        $installedFonts = brew list --cask 2>$null
        if ($LASTEXITCODE -eq 0 -and $installedFonts -contains $fontCask) {
            Write-Host "✓ $fontCask 已安装" -ForegroundColor Gray
            continue
        }

        Write-Host "正在安装 $fontCask..." -ForegroundColor Yellow
        brew install --cask $fontCask
    }

    return
}

if ($IsWindows) {
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    & (Join-Path $repoRoot 'windows/06installFonts.ps1') -Preset Core -WhatIf:$WhatIfPreference
    if ($LASTEXITCODE -ne 0) {
        throw "Windows 字体叶子退出码: $LASTEXITCODE"
    }
    return
}

Write-Warning '当前平台暂未配置字体安装方式。'
