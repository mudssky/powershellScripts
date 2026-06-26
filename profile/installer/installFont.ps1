$windowsFonts = @(
    'JetBrainsMono-NF',
    'FiraCode-NF'
)

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
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        throw '未找到 Scoop，无法安装 Windows Nerd Fonts。请先安装 scoop。'
    }

    scoop bucket add nerd-fonts
    foreach ($font in $windowsFonts) {
        $installedFonts = scoop list 2>$null
        if ($LASTEXITCODE -eq 0 -and $installedFonts -match [regex]::Escape($font)) {
            Write-Host "✓ $font 已安装" -ForegroundColor Gray
            continue
        }

        Write-Host "正在安装 $font..." -ForegroundColor Yellow
        scoop install $font
    }

    return
}

Write-Warning '当前平台暂未配置字体安装方式。'
