#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads and installs shaders for MPV.

.DESCRIPTION
    Downloads Anime4K, SSimSuperRes, Adaptive-Sharpen, KrigBilateral, and FSRCNNX shaders
    into categorized subdirectories in the 'shaders' directory of the specified MPV configuration root.

.PARAMETER MpvConfigRoot
    The root directory of the MPV configuration. Defaults to two levels up from this script.

.EXAMPLE
    .\download_shaders.ps1
    Downloads shaders to ../../shaders

.EXAMPLE
    .\download_shaders.ps1 -MpvConfigRoot "C:\Users\Name\scoop\persist\mpv\portable_config"
#>
[CmdletBinding()]
param(
    [string]$MpvConfigRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determine MPV Config Root if not provided
if (-not $MpvConfigRoot) {
    # Assuming script is in tools/install/, root is ../../
    $MpvConfigRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
}

$shaderRootDir = Join-Path $MpvConfigRoot "shaders"

# Ensure root shaders directory exists
if (-not (Test-Path $shaderRootDir)) {
    New-Item -ItemType Directory -Path $shaderRootDir | Out-Null
}

# -----------------------------------------------------------------------------
# 1. Download Common Shaders (SSimSuperRes, Adaptive-Sharpen, KrigBilateral)
# -----------------------------------------------------------------------------
$commonDir = Join-Path $shaderRootDir "Common"
if (-not (Test-Path $commonDir)) { New-Item -ItemType Directory -Path $commonDir | Out-Null }

# 使用不带 Hash 的 Raw 链接以获取最新版本，并避免 Hash 过期
$commonShaders = @{
    "SSimSuperRes.glsl"     = "https://gist.githubusercontent.com/igv/2364ffa6e81540f29cb7ab4c9bc05b6b/raw/SSimSuperRes.glsl"
    "adaptive-sharpen.glsl" = "https://gist.githubusercontent.com/igv/8a77e4eb8276753b54bb94c1c50c317e/raw/adaptive-sharpen.glsl"
    "KrigBilateral.glsl"    = "https://gist.githubusercontent.com/igv/a015fc885d5c22e6891820ad89555637/raw/KrigBilateral.glsl"
}

Write-Host "=== 下载通用着色器 (Common) ===" -ForegroundColor Cyan
foreach ($name in $commonShaders.Keys) {
    $url = $commonShaders[$name]
    $dest = Join-Path $commonDir $name
    Write-Host "下载 $name ..." -NoNewline
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
        Write-Host "  -> 成功" -ForegroundColor Green
    }
    catch {
        Write-Host "  -> 失败: $_" -ForegroundColor Red
    }
}

# 3. 下载 FSRCNNX (Upscale)
$fsrcnnxDir = Join-Path $shaderRootDir "FSRCNNX"
if (-not (Test-Path $fsrcnnxDir)) { New-Item -ItemType Directory -Path $fsrcnnxDir | Out-Null }

$fsrcnnxShaders = @{
    "FSRCNNX_x2_8-0-4-1.glsl" = "https://github.com/igv/FSRCNN-TensorFlow/releases/download/1.1/FSRCNNX_x2_8-0-4-1.glsl"
}

Write-Host "`n=== 下载 FSRCNNX (Upscale) ===" -ForegroundColor Cyan
foreach ($name in $fsrcnnxShaders.Keys) {
    $url = $fsrcnnxShaders[$name]
    $dest = Join-Path $fsrcnnxDir $name
    Write-Host "下载 $name ..." -NoNewline
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
        Write-Host "  -> 成功" -ForegroundColor Green
    }
    catch {
        Write-Host "  -> 失败: $_" -ForegroundColor Red
    }
}

# 4. 下载 Anime4K (Animation)
$anime4kDir = Join-Path $shaderRootDir "Anime4K"
if (-not (Test-Path $anime4kDir)) { New-Item -ItemType Directory -Path $anime4kDir | Out-Null }

# 使用 v4.0.1 版本
$anime4kUrl = "https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip"
$anime4kZip = Join-Path $shaderRootDir "Anime4K_v4.0.zip"

Write-Host "`n=== 下载 Anime4K (Animation) ===" -ForegroundColor Cyan
try {
    Write-Host "正在下载 Anime4K zip 包..."
    Invoke-WebRequest -Uri $anime4kUrl -OutFile $anime4kZip -ErrorAction Stop
    
    # 检查文件完整性
    $zipFile = Get-Item $anime4kZip
    if ($zipFile.Length -lt 1024) {
        throw "下载的文件过小 ($($zipFile.Length) bytes)，可能已损坏。"
    }

    Write-Host "下载完成，正在解压..." -ForegroundColor Green
    
    # 改回使用 Expand-Archive
    Expand-Archive -Path $anime4kZip -DestinationPath $anime4kDir -Force
    
    # 清理 zip
    if (Test-Path $anime4kZip) {
        Remove-Item $anime4kZip -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  -> Anime4K 安装成功" -ForegroundColor Green
}
catch {
    Write-Host "Anime4K 下载/安装失败: $_" -ForegroundColor Red
    # 尝试清理可能损坏的 zip
    if (Test-Path $anime4kZip) { Remove-Item $anime4kZip -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n所有着色器下载任务完成！" -ForegroundColor Cyan
Write-Host "存放目录: $shaderRootDir" -ForegroundColor Gray
