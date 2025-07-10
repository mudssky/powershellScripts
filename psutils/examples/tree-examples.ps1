<#
.SYNOPSIS
    Get-Tree函数使用示例
.DESCRIPTION
    此脚本演示了Get-Tree函数的各种使用方法和参数选项。
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-10
    用途: 演示Get-Tree函数的功能
#>

# 导入functions模块
Import-Module "$PSScriptRoot\..\index.psm1" -Force

Write-Host "=== Get-Tree 函数使用示例 ===" -ForegroundColor Green
Write-Host ""

# 示例1: 基本用法 - 显示当前目录的树状结构
Write-Host "示例1: 基本用法 - 显示当前目录结构（默认3层深度）" -ForegroundColor Yellow
Get-Tree -Path "$PSScriptRoot\.."
Write-Host ""

# 示例2: 指定最大深度
Write-Host "示例2: 指定最大深度为2层" -ForegroundColor Yellow
Get-Tree -Path "$PSScriptRoot\.." -MaxDepth 2
Write-Host ""

# 示例3: 只显示目录结构
Write-Host "示例3: 只显示目录结构，不显示文件" -ForegroundColor Yellow
Get-Tree -Path "$PSScriptRoot\.." -ShowFiles $false -MaxDepth 4
Write-Host ""

# 示例4: 排除特定文件类型
Write-Host "示例4: 排除.ps1文件" -ForegroundColor Yellow
Get-Tree -Path "$PSScriptRoot\..\examples" -Exclude @("*.ps1")
Write-Host ""

# 示例5: 限制每个目录显示的项目数量
Write-Host "示例5: 限制每个目录最多显示3个项目" -ForegroundColor Yellow
Get-Tree -Path "$PSScriptRoot\..\modules" -MaxItems 3
Write-Host ""

# 示例6: 显示隐藏文件（如果有的话）
Write-Host "示例6: 显示隐藏文件和目录" -ForegroundColor Yellow
Get-Tree -Path "$PSScriptRoot\.." -ShowHidden $true -MaxDepth 2
Write-Host ""

Write-Host "=== 示例演示完成 ===" -ForegroundColor Green
Write-Host "你可以使用 Get-Help Get-Tree -Full 查看完整的帮助文档" -ForegroundColor Cyan