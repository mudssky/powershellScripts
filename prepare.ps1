

#!/usr/bin/env pwsh

<#
.SYNOPSIS
    准备PowerShell脚本开发环境，自动配置PATH环境变量

.DESCRIPTION
    该脚本用于检测项目根目录和bin目录是否在PATH环境变量中，
    如果没有则自动添加，确保可以直接调用项目中的脚本。

.EXAMPLE
    .\prepare.ps1
    检测并添加必要的目录到PATH环境变量
#>

[CmdletBinding()]
param()

# 获取项目根目录
$ProjectRoot = $PSScriptRoot
$BinDir = Join-Path $ProjectRoot 'bin'

function Test-DirectoryInPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )
    
    # 获取当前PATH环境变量（优先User级别，然后Machine级别）
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $processPath = $env:PATH
    
    # 合并所有级别的PATH
    $allPaths = @()
    if ($userPath) { $allPaths += $userPath }
    if ($machinePath) { $allPaths += $machinePath }
    if ($processPath) { $allPaths += $processPath }
    
    # 获取目标目录的绝对路径
    try {
        $targetAbsolutePath = (Resolve-Path -Path $DirectoryPath).Path.ToLowerInvariant()
    }
    catch {
        Write-Warning "无法解析目标路径: $DirectoryPath"
        return $false
    }
    
    # 检查每个PATH条目
    foreach ($pathString in $allPaths) {
        $pathEntries = $pathString -split [IO.Path]::PathSeparator
        
        foreach ($entry in $pathEntries) {
            if ([string]::IsNullOrWhiteSpace($entry)) { continue }
            
            # 标准化路径条目
            $trimmedEntry = $entry.Trim()
            
            # 直接比较字符串（处理不存在路径的情况）
            if ($trimmedEntry -eq $DirectoryPath -or $trimmedEntry -eq $targetAbsolutePath) {
                return $true
            }
            
            # 如果路径存在，尝试解析后比较
            if (Test-Path $trimmedEntry) {
                try {
                    $resolvedEntry = (Resolve-Path -Path $trimmedEntry).Path.ToLowerInvariant()
                    if ($resolvedEntry -eq $targetAbsolutePath) {
                        return $true
                    }
                }
                catch {
                    # 解析失败，跳过
                    continue
                }
            }
        }
    }
    
    return $false
}

function Add-DirectoryToPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath,
        
        [Parameter(Mandatory = $true)]
        [string]$Scope
    )
    
    try {
        # 获取当前PATH
        $currentPath = [Environment]::GetEnvironmentVariable('PATH', $Scope)
        
        if ([string]::IsNullOrWhiteSpace($currentPath)) {
            $newPath = $DirectoryPath
        }
        else {
            $newPath = $currentPath + [IO.Path]::PathSeparator + $DirectoryPath
        }
        
        # 设置新的PATH
        [Environment]::SetEnvironmentVariable('PATH', $newPath, $Scope)
        
        Write-Host "成功将目录添加到$Scope PATH: $DirectoryPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "添加目录到PATH失败: $($_.Exception.Message)"
        return $false
    }
}

function Update-CurrentSessionPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )
    
    # 更新当前会话的PATH
    $env:PATH = $env:PATH + [IO.Path]::PathSeparator + $DirectoryPath
    Write-Host "已更新当前会话PATH: $DirectoryPath" -ForegroundColor Cyan
}

# 主执行逻辑
Write-Host "开始准备PowerShell脚本开发环境..." -ForegroundColor Green
Write-Host "项目根目录: $ProjectRoot" -ForegroundColor White
Write-Host "Bin目录: $BinDir" -ForegroundColor White

$changesMade = $false

# 检测项目根目录是否在PATH中
Write-Host "`n检测项目根目录是否在PATH中..." -ForegroundColor Yellow
if (Test-DirectoryInPath -DirectoryPath $ProjectRoot) {
    Write-Host "✓ 项目根目录已在PATH中" -ForegroundColor Green
}
else {
    Write-Host "✗ 项目根目录不在PATH中，正在添加..." -ForegroundColor Red
    
    if (Add-DirectoryToPath -DirectoryPath $ProjectRoot -Scope 'User') {
        Update-CurrentSessionPath -DirectoryPath $ProjectRoot
        $changesMade = $true
    }
}

# 确保bin目录存在并同步脚本
Write-Host "`n同步脚本到bin目录..." -ForegroundColor Yellow
try {
    & (Join-Path $ProjectRoot 'Manage-BinScripts.ps1') -Action 'sync' -Force
    $binExists = $true
}
catch {
    Write-Warning "同步脚本失败: $($_.Exception.Message)"
    $binExists = $false
}

if ( -not $IsWindows) {
    # 后续逻辑只在windows下执行
    return
}

# 检测bin目录是否在PATH中
if ($binExists -and (Test-Path $BinDir)) {
    Write-Host "`n检测bin目录是否在PATH中..." -ForegroundColor Yellow
    if (Test-DirectoryInPath -DirectoryPath $BinDir) {
        Write-Host "✓ Bin目录已在PATH中" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Bin目录不在PATH中，正在添加..." -ForegroundColor Red
        
        if (Add-DirectoryToPath -DirectoryPath $BinDir -Scope 'User') {
            Update-CurrentSessionPath -DirectoryPath $BinDir
            $changesMade = $true
        }
    }
}

# 输出结果
Write-Host "`n环境准备完成!" -ForegroundColor Green
if ($changesMade) {
    Write-Host "⚠️  环境变量已更新，建议重新启动PowerShell以确保所有更改生效" -ForegroundColor Yellow
}
else {
    Write-Host "✓ 所有必要的目录都已在PATH中" -ForegroundColor Green
}

Write-Host "`n当前PATH包含:" -ForegroundColor Cyan
$env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ -match [regex]::Escape($ProjectRoot) } | ForEach-Object {
    Write-Host "  - $_" -ForegroundColor White
}