#!/usr/bin/env pwsh
<#
.SYNOPSIS
    应用 yt-dlp 配置文件。
.DESCRIPTION
    此脚本将当前目录下的 `yt-dlp.conf` 配置文件部署到 yt-dlp 的标准配置目录中。
    在 Windows 上，目标路径为 `$env:APPDATA\yt-dlp\config`。
    在 Linux/macOS 上，目标路径为 `~/.config/yt-dlp/config`。
    脚本默认使用符号链接（Symlink）以保持配置同步，如果权限不足则退而使用复制。
.EXAMPLE
    .\Apply-YtdlpConfig.ps1
    将配置文件应用到系统。
.NOTES
    确保在运行此脚本之前，`yt-dlp.conf` 文件存在于当前目录下。
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [switch]$Force
)

function Apply-YtdlpConfig {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $sourceFileName = "yt-dlp.conf"
    $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath $sourceFileName

    if (-not (Test-Path $sourcePath)) {
        Write-Error "源文件不存在: $sourcePath"
        return
    }

    # 确定目标目录和文件名
    $destDir = ""
    $destFileName = "config" # yt-dlp 默认配置文件名通常不带后缀

    if ($IsWindows) {
        $destDir = Join-Path -Path $env:APPDATA -ChildPath "yt-dlp"
    }
    else {
        $homeDir = $env:HOME
        $xdgConfig = $env:XDG_CONFIG_HOME
        if ([string]::IsNullOrWhiteSpace($xdgConfig)) {
            $xdgConfig = Join-Path -Path $homeDir -ChildPath ".config"
        }
        $destDir = Join-Path -Path $xdgConfig -ChildPath "yt-dlp"
    }

    $destPath = Join-Path -Path $destDir -ChildPath $destFileName

    Write-Host "源文件: $sourcePath"
    Write-Host "目标路径: $destPath"

    # 创建目标目录
    if (-not (Test-Path $destDir)) {
        if ($PSCmdlet.ShouldProcess($destDir, "创建配置目录")) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            Write-Host "已创建目录: $destDir" -ForegroundColor Cyan
        }
    }

    # 处理已存在的目标文件
    if (Test-Path $destPath) {
        if ($Force -or $PSCmdlet.ShouldProcess($destPath, "备份并覆盖现有配置")) {
            $backupPath = "$destPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Move-Item -Path $destPath -Destination $backupPath -Force
            Write-Host "已备份原配置到: $backupPath" -ForegroundColor Yellow
        }
        else {
            Write-Host "目标文件已存在，使用 -Force 参数覆盖或在提示时确认。" -ForegroundColor Magenta
            return
        }
    }

    # 尝试创建符号链接，失败则复制
    if ($PSCmdlet.ShouldProcess($destPath, "部署配置文件")) {
        try {
            # 在 Windows 上创建符号链接通常需要管理员权限或启用开发者模式
            New-Item -ItemType SymbolicLink -Path $destPath -Target $sourcePath -ErrorAction Stop | Out-Null
            Write-Host "成功创建符号链接。" -ForegroundColor Green
        }
        catch {
            Write-Warning "创建符号链接失败（可能是权限不足），将退而使用复制。错误: $($_.Exception.Message)"
            Copy-Item -Path $sourcePath -Destination $destPath -Force
            Write-Host "成功复制配置文件。" -ForegroundColor Green
        }
    }
}

try {
    Apply-YtdlpConfig
}
catch {
    Write-Error "应用配置时发生意外错误: $($_.Exception.Message)"
}
