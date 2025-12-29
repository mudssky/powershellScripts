#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# SYNOPSIS: Manage-ClaudeConfig.ps1
# DESCRIPTION: 同步 Claude Code 配置到全局配置目录

$LocalPath = "c:\home\env\powershellScripts\ai\coding\claude\.claude"
$GlobalPath = Join-Path $HOME ".claude"

Write-Host "--- Claude Code 配置同步任务 ---" -ForegroundColor Cyan

# 1. 确保本地目录存在
if (-not (Test-Path -Path $LocalPath)) {
    Write-Host "[1/3] 创建本地配置目录: $LocalPath" -ForegroundColor Gray
    if ($PSCmdlet.ShouldProcess($LocalPath, "Create Directory")) {
        New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null
    }
}
else {
    Write-Host "[1/3] 本地配置目录已存在: $LocalPath" -ForegroundColor Gray
}

# 2. 处理全局配置
if (Test-Path -Path $GlobalPath) {
    $Item = Get-Item -Path $GlobalPath
    
    # 检查是否已经是软链接 (ReparsePoint)
    # 使用 .HasFlag() 方法检查属性
    if ($Item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
        $Target = $Item.Target
        if ($Target -eq $LocalPath) {
            Write-Host "[2/3] 全局配置已正确指向本地目录，无需操作。" -ForegroundColor Green
            return
        }
        else {
            Write-Host "[2/3] 全局配置是软链接但指向了错误位置: $Target" -ForegroundColor Yellow
            if ($PSCmdlet.ShouldProcess($GlobalPath, "Remove Old Symbolic Link")) {
                Remove-Item -Path $GlobalPath -Force
            }
        }
    }
    else {
        Write-Host "[2/3] 全局配置目录已存在，正在同步到本地..." -ForegroundColor Yellow
        
        # 复制内容到本地
        if ($PSCmdlet.ShouldProcess($GlobalPath, "Copy config to $LocalPath")) {
            # 如果本地已有同名文件，Force 会覆盖
            Copy-Item -Path (Join-Path $GlobalPath "*") -Destination $LocalPath -Recurse -Force
        }
        
        # 删除原全局目录
        Write-Host "正在删除原全局配置目录: $GlobalPath" -ForegroundColor Gray
        if ($PSCmdlet.ShouldProcess($GlobalPath, "Delete directory")) {
            Remove-Item -Path $GlobalPath -Recurse -Force
        }
    }
}
else {
    Write-Host "[2/3] 全局配置目录不存在，准备创建链接。" -ForegroundColor Gray
}

# 3. 创建软链接
try {
    Write-Host "[3/3] 创建软链接: $GlobalPath -> $LocalPath" -ForegroundColor Cyan
    if ($PSCmdlet.ShouldProcess($GlobalPath, "Create Symbolic Link to $LocalPath")) {
        New-Item -ItemType SymbolicLink -Path $GlobalPath -Target $LocalPath -Force | Out-Null
    }
    Write-Host "操作成功！Claude Code 现在将使用本地仓库中的配置。" -ForegroundColor Green
}
catch {
    Write-Error "创建软链接失败: $($_.Exception.Message)"
    Write-Host "请尝试以管理员权限运行此脚本。" -ForegroundColor Red
}
