<#
.SYNOPSIS
    演示如何发现 PSUtils 命令并读取标准 PowerShell 帮助。

.DESCRIPTION
    使用 Get-Command 和 Get-Help 浏览模块公共命令，不依赖已弃用的模块内帮助搜索 API。

.PARAMETER SmokeTest
    只执行最小的命令发现和帮助读取，用于自动 smoke 检查。

.OUTPUTS
    Microsoft.PowerShell.Commands.GenericMeasureInfo
    默认模式会输出按模块分类的命令统计；SmokeTest 模式不返回业务对象。

.EXAMPLE
    ./help-search-examples.ps1
    浏览模块命令、帮助示例和命令分类统计。

.EXAMPLE
    ./help-search-examples.ps1 -SmokeTest
    执行无交互、无副作用的最小 smoke 检查。
#>
param(
    [switch]$SmokeTest
)

Import-Module "$PSScriptRoot\..\psutils.psd1" -Force

if ($SmokeTest) {
    Get-Command Get-Tree -Module psutils -ErrorAction Stop | Out-Null
    Get-Help Get-Tree -Examples -ErrorAction Stop | Out-Null
    return
}

Write-Host '=== PSUtils 命令发现 ===' -ForegroundColor Cyan
Get-Command -Module psutils |
    Sort-Object Noun, Verb |
    Select-Object -First 20 Name, CommandType, Source |
    Format-Table -AutoSize

Write-Host '=== Get-Tree 帮助示例 ===' -ForegroundColor Cyan
Get-Help Get-Tree -Examples

Write-Host '=== Config 相关命令 ===' -ForegroundColor Cyan
Get-Command -Module psutils -Name '*Config*' |
    Sort-Object Name |
    Format-Table Name, Source -AutoSize

Write-Host '=== 命令类型统计 ===' -ForegroundColor Cyan
Get-Command -Module psutils | Group-Object CommandType | Sort-Object Name
