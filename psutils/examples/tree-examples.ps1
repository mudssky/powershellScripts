<#
.SYNOPSIS
    Get-Tree函数使用示例
.DESCRIPTION
    此脚本演示了Get-Tree函数的各种使用方法和参数选项。

.PARAMETER SmokeTest
    只显示 examples 目录的一层结构，用于自动 smoke 检查。

.OUTPUTS
    无。树结构直接写入控制台。

.EXAMPLE
    ./tree-examples.ps1
    依次演示 Get-Tree 的常用参数。

.EXAMPLE
    ./tree-examples.ps1 -SmokeTest
    执行无副作用的最小 smoke 检查。
#>
param(
    [switch]$SmokeTest
)

# 示例使用规范 manifest，确保与真实模块导出契约一致。
Import-Module "$PSScriptRoot\..\psutils.psd1" -Force

if ($SmokeTest) {
    Get-Tree -Path $PSScriptRoot -MaxDepth 1 -MaxItems 5
    return
}

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
