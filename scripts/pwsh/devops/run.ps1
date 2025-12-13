#!/usr/bin/env pwsh

<#
.SYNOPSIS
    统一的脚本运行入口

.DESCRIPTION
    该脚本提供统一的入口来运行项目中的任何PowerShell脚本。
    可以通过脚本名称或分类来查找和运行脚本，支持模糊搜索。

.PARAMETER ScriptName
    要运行的脚本名称（支持模糊匹配）

.PARAMETER Category
    脚本分类：media, filesystem, network, devops, misc

.PARAMETER List
    列出所有可用脚本

.PARAMETER Search
    搜索包含关键字的脚本

.PARAMETER CategoryList
    按分类列出脚本

.EXAMPLE
    .\run.ps1 -List
    列出所有可用脚本

.EXAMPLE
    .\run.ps1 -Category media
    列出媒体类脚本

.EXAMPLE
    .\run.ps1 VideoToAudio
    运行VideoToAudio脚本

.EXAMPLE
    .\run.ps1 -Search video
    搜索包含video关键字的脚本

.EXAMPLE
    .\run.ps1 VideoToAudio -Param1 value1 -Param2 value2
    运行脚本并传递参数
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ScriptName,
    
    [ValidateSet('media', 'filesystem', 'network', 'devops', 'misc')]
    [string]$Category,
    
    [switch]$List,
    
    [string]$Search,
    
    [switch]$CategoryList,
    
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

# 获取项目根目录
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ScriptsDir = Join-Path $ProjectRoot 'scripts\pwsh'

# 获取所有脚本信息
function Get-AllScripts {
    $scripts = @()
    
    Get-ChildItem -Path $ScriptsDir -Filter '*.ps1' -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Replace($ProjectRoot, '').TrimStart('\')
        $category = Split-Path (Split-Path $_.FullName -Parent) -Leaf
        
        $scripts += [PSCustomObject]@{
            Name         = $_.Name
            BaseName     = $_.BaseName
            Category     = $category
            Path         = $_.FullName
            RelativePath = $relativePath
        }
    }
    
    return $scripts | Sort-Object Category, Name
}

# 显示所有脚本
function Show-AllScripts {
    $scripts = Get-AllScripts
    
    Write-Host "`n=== 所有可用脚本 ===" -ForegroundColor Green
    Write-Host "总计: $($scripts.Count) 个脚本`n" -ForegroundColor White
    
    $currentCategory = ""
    foreach ($script in $scripts) {
        if ($script.Category -ne $currentCategory) {
            $currentCategory = $script.Category
            Write-Host "`n[$($currentCategory.ToUpper())]" -ForegroundColor Yellow
            Write-Host ("-" * 20) -ForegroundColor Gray
        }
        
        Write-Host "  $($script.BaseName)" -ForegroundColor Cyan
    }
    
    Write-Host "`n使用示例:" -ForegroundColor Magenta
    Write-Host "  .\run.ps1 VideoToAudio" -ForegroundColor White
    Write-Host "  .\run.ps1 -Category media" -ForegroundColor White
    Write-Host "  .\run.ps1 -Search video" -ForegroundColor White
}

# 按分类显示脚本
function Show-CategoryScripts {
    param([string]$CategoryName)
    
    $scripts = Get-AllScripts | Where-Object { $_.Category -eq $CategoryName }
    
    if ($scripts.Count -eq 0) {
        Write-Warning "分类 '$CategoryName' 中没有找到脚本"
        return
    }
    
    Write-Host "`n=== [$($CategoryName.ToUpper())] 分类脚本 ===" -ForegroundColor Green
    Write-Host "总计: $($scripts.Count) 个脚本`n" -ForegroundColor White
    
    foreach ($script in $scripts) {
        Write-Host "  $($script.BaseName)" -ForegroundColor Cyan
        Write-Host "    路径: $($script.RelativePath)" -ForegroundColor Gray
    }
}

# 搜索脚本
function Search-Scripts {
    param([string]$Keyword)
    
    $scripts = Get-AllScripts | Where-Object { 
        $_.Name -like "*$Keyword*" -or 
        $_.BaseName -like "*$Keyword*" -or 
        $_.Category -like "*$Keyword*"
    }
    
    if ($scripts.Count -eq 0) {
        Write-Warning "未找到包含关键字 '$Keyword' 的脚本"
        return
    }
    
    Write-Host "`n=== 搜索结果: '$Keyword' ===" -ForegroundColor Green
    Write-Host "找到 $($scripts.Count) 个匹配的脚本`n" -ForegroundColor White
    
    foreach ($script in $scripts) {
        Write-Host "  [$($script.Category)] $($script.BaseName)" -ForegroundColor Cyan
        Write-Host "    路径: $($script.RelativePath)" -ForegroundColor Gray
    }
}

# 运行脚本
function Invoke-Script {
    param([string]$ScriptName, [string[]]$Arguments)
    
    $scripts = Get-AllScripts
    
    # 查找匹配的脚本
    $matchedScripts = $scripts | Where-Object { 
        $_.BaseName -eq $ScriptName -or 
        $_.BaseName -like "*$ScriptName*" -or
        $_.Name -eq "$ScriptName.ps1"
    }
    
    if ($matchedScripts.Count -eq 0) {
        Write-Error "未找到脚本: $ScriptName"
        Write-Host "使用 .\run.ps1 -List 查看所有可用脚本" -ForegroundColor Yellow
        return
    }
    
    if ($matchedScripts.Count -gt 1) {
        Write-Host "找到多个匹配的脚本:" -ForegroundColor Yellow
        $matchedScripts | ForEach-Object {
            Write-Host "  [$($_.Category)] $($_.BaseName)" -ForegroundColor Cyan
        }
        Write-Host "`n请使用更具体的名称" -ForegroundColor Yellow
        return
    }
    
    $targetScript = $matchedScripts[0]
    
    try {
        Write-Host "运行脚本: $($targetScript.BaseName)" -ForegroundColor Green
        Write-Host "路径: $($targetScript.RelativePath)" -ForegroundColor Gray
        
        # 构建参数字符串
        $argString = $Arguments -join ' '
        
        if ($Arguments.Count -gt 0) {
            Write-Host "参数: $($Arguments -join ' ')" -ForegroundColor Gray
            & pwsh -ExecutionPolicy Bypass -File $targetScript.Path $Arguments
        }
        else {
            & pwsh -ExecutionPolicy Bypass -File $targetScript.Path
        }
    }
    catch {
        Write-Error "运行脚本失败: $($_.Exception.Message)"
    }
}

# 主逻辑
if ($List) {
    Show-AllScripts
}
elseif ($Category) {
    Show-CategoryScripts -CategoryName $Category
}
elseif ($Search) {
    Search-Scripts -Keyword $Search
}
elseif ($ScriptName) {
    Invoke-Script -ScriptName $ScriptName -Arguments $RemainingArgs
}
else {
    Write-Host "`n=== PowerShell脚本统一运行入口 ===" -ForegroundColor Green
    Write-Host "`n使用方法:" -ForegroundColor Cyan
    Write-Host "  .\run.ps1 -List                    # 列出所有脚本" -ForegroundColor White
    Write-Host "  .\run.ps1 -Category <分类>         # 按分类列出脚本" -ForegroundColor White
    Write-Host "  .\run.ps1 -Search <关键字>         # 搜索脚本" -ForegroundColor White
    Write-Host "  .\run.ps1 <脚本名> [参数...]       # 运行指定脚本" -ForegroundColor White
    Write-Host "`n可用分类:" -ForegroundColor Cyan
    Write-Host "  media, filesystem, network, devops, misc" -ForegroundColor White
    Write-Host "`n示例:" -ForegroundColor Cyan
    Write-Host "  .\run.ps1 VideoToAudio" -ForegroundColor White
    Write-Host "  .\run.ps1 -Category media" -ForegroundColor White
    Write-Host "  .\run.ps1 -Search video" -ForegroundColor White
}