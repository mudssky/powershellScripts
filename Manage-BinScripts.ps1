#!/usr/bin/env pwsh

<#
.SYNOPSIS
    管理bin目录脚本映射的自动化工具

.DESCRIPTION
    该脚本用于自动生成bin目录下的脚本映射，将scripts/pwsh/目录下的所有PowerShell脚本
    复制到bin目录，保持原始文件名，这样可以将bin目录加入环境变量PATH后直接调用脚本。

.PARAMETER Action
    要执行的操作：'sync'（同步脚本到bin目录）或'clean'（清理bin目录）

.PARAMETER Force
    强制覆盖bin目录中已存在的文件

.EXAMPLE
    .\Manage-BinScripts.ps1 -Action sync
    同步所有PowerShell脚本到bin目录

.EXAMPLE
    .\Manage-BinScripts.ps1 -Action clean
    清理bin目录中的所有脚本文件
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('sync', 'clean')]
    [string]$Action,
    
    [switch]$Force
)

# 获取项目根目录
$ProjectRoot = $PSScriptRoot
$ScriptsDir = Join-Path $ProjectRoot 'scripts\pwsh'
$BinDir = Join-Path $ProjectRoot 'bin'

function Sync-BinScripts {
    param([switch]$Force)
    
    Write-Host "开始同步PowerShell脚本到bin目录..." -ForegroundColor Green
    
    if (-not (Test-Path $ScriptsDir)) {
        Write-Error "scripts目录不存在: $ScriptsDir"
        return
    }
    
    # 确保bin目录存在
    if (-not (Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
        Write-Host "创建bin目录: $BinDir" -ForegroundColor Yellow
    }
    
    # 获取所有PowerShell脚本
    $psScripts = Get-ChildItem -Path $ScriptsDir -Filter '*.ps1' -Recurse
    
    if ($psScripts.Count -eq 0) {
        Write-Warning "在 $ScriptsDir 中未找到PowerShell脚本"
        return
    }
    
    $syncedCount = 0
    $skippedCount = 0
    
    foreach ($script in $psScripts) {
        $targetPath = Join-Path $BinDir $script.Name
        
        # 检查目标文件是否已存在
        if ((Test-Path $targetPath) -and -not $Force) {
            Write-Host "跳过已存在的文件: $($script.Name)" -ForegroundColor Yellow
            $skippedCount++
            continue
        }
        
        try {
            # 复制脚本文件
            Copy-Item -Path $script.FullName -Destination $targetPath -Force:$Force
            Write-Host "同步: $($script.Name) -> bin\$($script.Name)" -ForegroundColor Cyan
            $syncedCount++
        }
        catch {
            Write-Error "复制脚本失败 $($script.Name): $($_.Exception.Message)"
        }
    }
    
    Write-Host "`n同步完成!" -ForegroundColor Green
    Write-Host "同步文件数: $syncedCount" -ForegroundColor White
    Write-Host "跳过文件数: $skippedCount" -ForegroundColor White
    Write-Host "bin目录路径: $BinDir" -ForegroundColor White
    Write-Host "`n提示: 将 $BinDir 添加到环境变量PATH后，可直接在命令行调用任何脚本" -ForegroundColor Magenta
}

function Clean-BinScripts {
    Write-Host "开始清理bin目录中的脚本文件..." -ForegroundColor Green
    
    if (-not (Test-Path $BinDir)) {
        Write-Warning "bin目录不存在: $BinDir"
        return
    }
    
    $binScripts = Get-ChildItem -Path $BinDir -Filter '*.ps1'
    
    if ($binScripts.Count -eq 0) {
        Write-Host "bin目录中没有PowerShell脚本文件" -ForegroundColor Yellow
        return
    }
    
    $removedCount = 0
    
    foreach ($script in $binScripts) {
        try {
            Remove-Item -Path $script.FullName -Force
            Write-Host "删除: $($script.Name)" -ForegroundColor Red
            $removedCount++
        }
        catch {
            Write-Error "删除文件失败 $($script.Name): $($_.Exception.Message)"
        }
    }
    
    Write-Host "`n清理完成!" -ForegroundColor Green
    Write-Host "删除文件数: $removedCount" -ForegroundColor White
}

# 执行相应操作
switch ($Action) {
    'sync' {
        Sync-BinScripts -Force:$Force
    }
    'clean' {
        Clean-BinScripts
    }
}

Write-Host "`n使用示例:" -ForegroundColor Cyan
Write-Host "  同步脚本: .\Manage-BinScripts.ps1 -Action sync" -ForegroundColor White
Write-Host "  强制同步: .\Manage-BinScripts.ps1 -Action sync -Force" -ForegroundColor White
Write-Host "  清理脚本: .\Manage-BinScripts.ps1 -Action clean" -ForegroundColor White