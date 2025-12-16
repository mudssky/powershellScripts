#!/usr/bin/env pwsh

<#
.SYNOPSIS
    清理环境变量中无用的路径，移除不存在或没有可执行文件的路径
.DESCRIPTION
    此脚本会扫描指定环境变量目标（Machine或User）的PATH环境变量，
    识别并移除以下类型的无效路径：
    1. 不存在的目录路径
    2. 存在但不包含任何可执行文件（.exe, .cmd, .bat, .ps1）的目录
    3. 重复的路径项
    4. User PATH中与System PATH重复的路径项（仅在清理User级别时）
    
    脚本会在执行清理前显示详细的分析结果并要求用户确认。
.PARAMETER EnvTarget
    指定要清理的环境变量目标：
    - User: 清理当前用户的PATH环境变量（默认，会自动检测与System PATH的重复）
    - Machine: 清理系统级PATH环境变量（需要管理员权限）
.PARAMETER WhatIf
    仅显示将要执行的操作，不实际修改环境变量
.PARAMETER Force
    跳过用户确认，直接执行清理操作
.PARAMETER BackupPath
    指定备份文件的保存路径，默认保存到脚本目录下的backup文件夹
.PARAMETER SkipSystemPathCheck
    跳过与System PATH的重复检查（仅在清理User级别时有效）
.NOTES
    - 建议在执行前备份当前的PATH环境变量
    - 清理Machine级别的环境变量需要管理员权限
    - 脚本会自动创建备份文件以便恢复
.EXAMPLE
    .\cleanEnvPath.ps1
    使用默认设置清理当前用户的PATH环境变量
.EXAMPLE
    .\cleanEnvPath.ps1 -EnvTarget Machine -Verbose
    清理系统级PATH环境变量并显示详细信息
.EXAMPLE
    .\cleanEnvPath.ps1 -WhatIf
    预览清理操作但不实际执行
.EXAMPLE
    .\cleanEnvPath.ps1 -Force -BackupPath "C:\Backup"
    强制执行清理并将备份保存到指定路径
.EXAMPLE
    .\cleanEnvPath.ps1 -EnvTarget User -SkipSystemPathCheck
    清理用户PATH但跳过与System PATH的重复检查
#>


[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [ValidateSet('Machine', 'User')]
    [string]$EnvTarget = 'User',
    
    [switch]$Force,
    
    [string]$BackupPath = (Join-Path $PSScriptRoot "backup"),
    
    [switch]$SkipSystemPathCheck
)



# 检查管理员权限（当操作Machine级别环境变量时）
if ($EnvTarget -eq 'Machine') {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "操作系统级环境变量需要管理员权限，请以管理员身份运行PowerShell"
        exit 1
    }
}

# 创建备份目录
if (-not (Test-Path $BackupPath)) {
    try {
        New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        Write-Verbose "创建备份目录: $BackupPath"
    }
    catch {
        Write-Error "无法创建备份目录 $BackupPath : $_"
        exit 1
    }
}

# 获取当前PATH环境变量
try {
    $currentPathStr = Get-EnvParam -ParamName 'Path' -EnvTarget $EnvTarget
    if ([string]::IsNullOrEmpty($currentPathStr)) {
        Write-Warning "$EnvTarget 级别的PATH环境变量为空或未设置"
        exit 0
    }
}
catch {
    Write-Error "无法获取 $EnvTarget 级别的PATH环境变量: $_"
    exit 1
}

# 获取System PATH用于重复检测（仅在清理User级别且未跳过检查时）
$systemPathList = @()
if ($EnvTarget -eq 'User' -and -not $SkipSystemPathCheck) {
    try {
        $systemPathStr = Get-EnvParam -ParamName 'Path' -EnvTarget 'Machine'
        if (-not [string]::IsNullOrEmpty($systemPathStr)) {
            $systemPathList = ($systemPathStr -split ';') | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim().TrimEnd('\').ToLower() }
            Write-Verbose "已获取System PATH用于重复检测，包含 $($systemPathList.Count) 个路径"
        }
    }
    catch {
        Write-Warning "无法获取System PATH进行重复检测: $_"
    }
}

# 创建备份
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFileName = "PATH_${EnvTarget}_${timestamp}.txt"
$backupFilePath = Join-Path $BackupPath $backupFileName

try {
    $currentPathStr | Out-File -FilePath $backupFilePath -Encoding UTF8
    Write-Host "✓ 已创建备份文件: $backupFilePath" -ForegroundColor Green
}
catch {
    Write-Error "无法创建备份文件: $_"
    exit 1
}

# 解析和分析PATH
$currentPathList = ($currentPathStr -split ';') | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
$uniquePathList = $currentPathList | Select-Object -Unique

Write-Host "`n📋 当前 $EnvTarget 级别PATH分析:" -ForegroundColor Cyan
Write-Host "   总路径数: $($currentPathList.Count)" -ForegroundColor Yellow
Write-Host "   唯一路径数: $($uniquePathList.Count)" -ForegroundColor Yellow
Write-Host "   重复路径数: $($currentPathList.Count - $uniquePathList.Count)" -ForegroundColor Yellow

if ($EnvTarget -eq 'User' -and -not $SkipSystemPathCheck -and $systemPathList.Count -gt 0) {
    Write-Host "   System PATH路径数: $($systemPathList.Count)" -ForegroundColor Cyan
}

# 分类路径
$validPaths = @()
$invalidPaths = @()
$duplicatePaths = @()
$systemDuplicatePaths = @()
$processedPaths = @{}

Write-Host "`n🔍 正在分析路径有效性..." -ForegroundColor Cyan
$progressCount = 0

foreach ($path in $currentPathList) {
    $progressCount++
    $normalizedPath = $path.Trim().TrimEnd('\').ToLower()
    
    Write-Progress -Activity "分析PATH路径" -Status "处理: $path" -PercentComplete (($progressCount / $currentPathList.Count) * 100)
    
    # 检查与当前级别内的重复路径
    if ($processedPaths.ContainsKey($normalizedPath)) {
        $duplicatePaths += $path
        Write-Verbose "发现重复路径: $path"
        continue
    }
    
    $processedPaths[$normalizedPath] = $true
    
    # 检查与System PATH的重复（仅在清理User级别时）
    if ($EnvTarget -eq 'User' -and -not $SkipSystemPathCheck -and $systemPathList -contains $normalizedPath) {
        $systemDuplicatePaths += $path
        Write-Verbose "发现与System PATH重复的路径: $path"
        continue
    }
    
    # 检查路径有效性
    if (Test-PathHasExe -Path $path) {
        $validPaths += $path
        Write-Verbose "有效路径: $path"
    }
    else {
        $invalidPaths += $path
        Write-Verbose "无效路径: $path"
    }
}

Write-Progress -Activity "分析PATH路径" -Completed

# 显示分析结果
Write-Host "`n📊 分析结果:" -ForegroundColor Cyan
Write-Host "   ✅ 有效路径: $($validPaths.Count)" -ForegroundColor Green
Write-Host "   ❌ 无效路径: $($invalidPaths.Count)" -ForegroundColor Red
Write-Host "   🔄 重复路径: $($duplicatePaths.Count)" -ForegroundColor Yellow

if ($EnvTarget -eq 'User' -and -not $SkipSystemPathCheck) {
    Write-Host "   🔗 与System重复: $($systemDuplicatePaths.Count)" -ForegroundColor Magenta
}

$totalProblemsCount = $invalidPaths.Count + $duplicatePaths.Count + $systemDuplicatePaths.Count
if ($totalProblemsCount -eq 0) {
    Write-Host "`n🎉 PATH环境变量已经是最优状态，无需清理!" -ForegroundColor Green
    exit 0
}

# 显示详细信息
if ($invalidPaths.Count -gt 0) {
    Write-Host "`n❌ 将被移除的无效路径:" -ForegroundColor Red
    $invalidPaths | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
}

if ($duplicatePaths.Count -gt 0) {
    Write-Host "`n🔄 将被移除的重复路径:" -ForegroundColor Yellow
    $duplicatePaths | ForEach-Object { Write-Host "   $_" -ForegroundColor Yellow }
}

if ($systemDuplicatePaths.Count -gt 0) {
    Write-Host "`n🔗 将被移除的与System PATH重复路径:" -ForegroundColor Magenta
    $systemDuplicatePaths | ForEach-Object { Write-Host "   $_" -ForegroundColor Magenta }
}

if ($validPaths.Count -gt 0) {
    Write-Host "`n✅ 将保留的有效路径:" -ForegroundColor Green
    $validPaths | ForEach-Object { Write-Host "   $_" -ForegroundColor Green }
}

# 用户确认和执行
$shouldProceed = $false

if ($PSCmdlet.ShouldProcess("$EnvTarget 级别的PATH环境变量", "清理无效和重复路径")) {
    if ($Force) {
        $shouldProceed = $true
        Write-Host "`n⚡ 使用 -Force 参数，跳过确认直接执行" -ForegroundColor Yellow
    }
    else {
        # 显示操作摘要
        Write-Host "`n📝 操作摘要:" -ForegroundColor Cyan
        Write-Host "   🎯 目标: $EnvTarget 级别PATH环境变量" -ForegroundColor White
        Write-Host "   📁 备份位置: $backupFilePath" -ForegroundColor White
        Write-Host "   🗑️  将移除: $($invalidPaths.Count + $duplicatePaths.Count + $systemDuplicatePaths.Count) 个路径" -ForegroundColor White
        if ($systemDuplicatePaths.Count -gt 0) {
            Write-Host "     ├─ 无效路径: $($invalidPaths.Count)" -ForegroundColor White
            Write-Host "     ├─ 重复路径: $($duplicatePaths.Count)" -ForegroundColor White
            Write-Host "     └─ 与System重复: $($systemDuplicatePaths.Count)" -ForegroundColor White
        }
        Write-Host "   ✅ 将保留: $($validPaths.Count) 个路径" -ForegroundColor White
        
        $title = "🔧 PATH环境变量清理确认"
        $message = "是否继续执行清理操作？此操作将修改 $EnvTarget 级别的PATH环境变量。"
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "确认执行清理操作"
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "取消操作"
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
        $result = $host.UI.PromptForChoice($title, $message, $options, 1)  # 默认选中No，更安全
        
        $shouldProceed = ($result -eq 0)
    }
}

if ($shouldProceed) {
    Write-Host "`n🚀 开始执行清理操作..." -ForegroundColor Green
    
    try {
        # 构建最终的PATH字符串
        $finalPathStr = ($validPaths -join ';')
        
        Write-Verbose "最终PATH内容: $finalPathStr"
        Write-Host "📝 正在更新 $EnvTarget 级别的PATH环境变量..." -ForegroundColor Cyan
        
        # 设置新的PATH环境变量
        Set-EnvPath -EnvTarget $EnvTarget -PathStr $finalPathStr
        
        # 显示成功信息
        Write-Host "`n🎉 PATH环境变量清理完成!" -ForegroundColor Green
        Write-Host "📊 清理统计:" -ForegroundColor Cyan
        Write-Host "   ✅ 保留有效路径: $($validPaths.Count)" -ForegroundColor Green
        Write-Host "   🗑️  移除无效路径: $($invalidPaths.Count)" -ForegroundColor Red
        Write-Host "   🔄 移除重复路径: $($duplicatePaths.Count)" -ForegroundColor Yellow
        if ($systemDuplicatePaths.Count -gt 0) {
            Write-Host "   🔗 移除与System重复路径: $($systemDuplicatePaths.Count)" -ForegroundColor Magenta
        }
        Write-Host "   💾 备份文件: $backupFilePath" -ForegroundColor Blue
        
        # 提示重启或重新加载
        Write-Host "`n💡 提示:" -ForegroundColor Yellow
        Write-Host "   • 更改已生效，新打开的终端将使用清理后的PATH" -ForegroundColor White
        Write-Host "   • 当前终端可能需要重启才能看到更改" -ForegroundColor White
        Write-Host "   • 如需恢复，请使用备份文件: $backupFilePath" -ForegroundColor White
    }
    catch {
        Write-Error "清理操作失败: $_"
        Write-Host "💾 可以使用备份文件恢复: $backupFilePath" -ForegroundColor Yellow
        exit 1
    }
}
else {
    Write-Host "`n❌ 用户取消操作，PATH环境变量未被修改" -ForegroundColor Yellow
    Write-Host "💾 备份文件已保存: $backupFilePath" -ForegroundColor Blue
    exit 0
}


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
