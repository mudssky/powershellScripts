<#
.SYNOPSIS
    测试脚本示例

.DESCRIPTION
    这是一个用于测试help.psm1模块中脚本搜索功能的示例脚本。
    它演示了如何在.ps1文件中编写标准的PowerShell帮助注释。

.PARAMETER Name
    要处理的名称

.PARAMETER Count
    处理次数，默认为1

.PARAMETER Force
    是否强制执行操作

.EXAMPLE
    .\test-script-example.ps1 -Name "Test" -Count 3
    使用指定名称和次数运行脚本

.EXAMPLE
    .\test-script-example.ps1 -Name "Demo" -Force
    强制执行操作

.NOTES
    作者: mudssky
    版本: 1.0.0
    创建日期: 2024
    用途: 测试脚本帮助功能
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    
    [Parameter()]
    [int]$Count = 1,
    
    [Parameter()]
    [switch]$Force
)

Write-Host "测试脚本运行中..." -ForegroundColor Green
Write-Host "名称: $Name" -ForegroundColor Cyan
Write-Host "次数: $Count" -ForegroundColor Cyan
Write-Host "强制: $Force" -ForegroundColor Cyan

for ($i = 1; $i -le $Count; $i++) {
    Write-Host "第 $i 次处理: $Name" -ForegroundColor Yellow
    Start-Sleep -Milliseconds 100
}

Write-Host "脚本执行完成!" -ForegroundColor Green