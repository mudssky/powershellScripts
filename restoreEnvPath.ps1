#!/usr/bin/env pwsh

<#
.SYNOPSIS
    从备份文件恢复PATH环境变量
.DESCRIPTION
    此脚本用于从cleanEnvPath.ps1创建的备份文件中恢复PATH环境变量。
    支持从指定的备份文件恢复，或者从备份目录中选择最新的备份文件。
.PARAMETER BackupFilePath
    指定要恢复的备份文件路径
.PARAMETER BackupDirectory
    指定备份文件所在的目录，脚本将列出可用的备份文件供选择
.PARAMETER EnvTarget
    指定要恢复的环境变量目标（Machine或User）
.PARAMETER Force
    跳过用户确认，直接执行恢复操作
.EXAMPLE
    .\restoreEnvPath.ps1 -BackupFilePath "C:\backup\PATH_User_20231201_143022.txt"
    从指定的备份文件恢复用户级PATH环境变量
.EXAMPLE
    .\restoreEnvPath.ps1 -BackupDirectory "C:\backup" -EnvTarget User
    从备份目录中选择文件恢复用户级PATH环境变量
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(ParameterSetName = 'FilePath', Mandatory = $true)]
    [string]$BackupFilePath,
    
    [Parameter(ParameterSetName = 'Directory')]
    [string]$BackupDirectory = (Join-Path $PSScriptRoot "backup"),
    
    [ValidateSet('Machine', 'User')]
    [string]$EnvTarget = 'User',
    
    [switch]$Force
)

# 导入必需的模块
try {
    Import-Module (Resolve-Path -Path $PSScriptRoot/psutils) -ErrorAction Stop
}
catch {
    Write-Error "无法导入psutils模块: $_"
    exit 1
}

# 检查管理员权限（当操作Machine级别环境变量时）
if ($EnvTarget -eq 'Machine') {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "操作系统级环境变量需要管理员权限，请以管理员身份运行PowerShell"
        exit 1
    }
}

# 确定备份文件
if ($PSCmdlet.ParameterSetName -eq 'FilePath') {
    if (-not (Test-Path $BackupFilePath)) {
        Write-Error "备份文件不存在: $BackupFilePath"
        exit 1
    }
    $selectedBackupFile = $BackupFilePath
}
else {
    # 从目录中选择备份文件
    if (-not (Test-Path $BackupDirectory)) {
        Write-Error "备份目录不存在: $BackupDirectory"
        exit 1
    }
    
    $backupFiles = Get-ChildItem -Path $BackupDirectory -Filter "PATH_${EnvTarget}_*.txt" | Sort-Object LastWriteTime -Descending
    
    if ($backupFiles.Count -eq 0) {
        Write-Error "在目录 $BackupDirectory 中未找到 $EnvTarget 级别的备份文件"
        exit 1
    }
    
    if ($backupFiles.Count -eq 1) {
        $selectedBackupFile = $backupFiles[0].FullName
        Write-Host "🔍 找到备份文件: $($backupFiles[0].Name)" -ForegroundColor Green
    }
    else {
        Write-Host "📁 在目录 $BackupDirectory 中找到多个备份文件:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $backupFiles.Count; $i++) {
            $file = $backupFiles[$i]
            Write-Host "   [$($i + 1)] $($file.Name) (创建时间: $($file.LastWriteTime))" -ForegroundColor Yellow
        }
        
        do {
            $selection = Read-Host "请选择要恢复的备份文件 (1-$($backupFiles.Count))"
            $selectionIndex = [int]$selection - 1
        } while ($selectionIndex -lt 0 -or $selectionIndex -ge $backupFiles.Count)
        
        $selectedBackupFile = $backupFiles[$selectionIndex].FullName
    }
}

# 读取备份文件内容
try {
    $backupContent = Get-Content -Path $selectedBackupFile -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($backupContent)) {
        Write-Error "备份文件内容为空: $selectedBackupFile"
        exit 1
    }
    $backupContent = $backupContent.Trim()
}
catch {
    Write-Error "无法读取备份文件 $selectedBackupFile : $_"
    exit 1
}

# 显示恢复信息
Write-Host "📋 恢复操作信息:" -ForegroundColor Cyan
Write-Host "   🎯 目标: $EnvTarget 级别PATH环境变量" -ForegroundColor White
Write-Host "   📁 备份文件: $selectedBackupFile" -ForegroundColor White
Write-Host "   📅 备份时间: $((Get-Item $selectedBackupFile).LastWriteTime)" -ForegroundColor White

# 分析备份内容
$backupPaths = ($backupContent -split ';') | Where-Object { $_.Trim() -ne '' }
Write-Host "   📊 备份包含路径数: $($backupPaths.Count)" -ForegroundColor White

# 获取当前PATH进行对比
try {
    $currentPathStr = Get-EnvParam -ParamName 'Path' -EnvTarget $EnvTarget
    $currentPaths = ($currentPathStr -split ';') | Where-Object { $_.Trim() -ne '' }
    Write-Host "   📊 当前路径数: $($currentPaths.Count)" -ForegroundColor White
}
catch {
    Write-Warning "无法获取当前PATH环境变量进行对比"
}

# 用户确认
$shouldProceed = $false

if ($PSCmdlet.ShouldProcess("$EnvTarget 级别的PATH环境变量", "从备份恢复")) {
    if ($Force) {
        $shouldProceed = $true
        Write-Host "⚡ 使用 -Force 参数，跳过确认直接执行" -ForegroundColor Yellow
    }
    else {
        $title = "🔄 PATH环境变量恢复确认"
        $message = "是否继续执行恢复操作？此操作将覆盖当前的 $EnvTarget 级别PATH环境变量。"
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "确认执行恢复操作"
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "取消操作"
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
        $result = $host.UI.PromptForChoice($title, $message, $options, 1)  # 默认选中No
        
        $shouldProceed = ($result -eq 0)
    }
}

if ($shouldProceed) {
    Write-Host "🚀 开始执行恢复操作..." -ForegroundColor Green
    
    try {
        # 创建当前状态的备份
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $preRestoreBackupPath = Join-Path (Split-Path $selectedBackupFile) "PATH_${EnvTarget}_PreRestore_${timestamp}.txt"
        
        if (-not [string]::IsNullOrEmpty($currentPathStr)) {
            $currentPathStr | Out-File -FilePath $preRestoreBackupPath -Encoding UTF8
            Write-Host "💾 已创建恢复前备份: $preRestoreBackupPath" -ForegroundColor Blue
        }
        
        # 执行恢复
        Write-Host "📝 正在恢复 $EnvTarget 级别的PATH环境变量..." -ForegroundColor Cyan
        Set-EnvPath -EnvTarget $EnvTarget -PathStr $backupContent
        
        # 显示成功信息
        Write-Host "🎉 PATH环境变量恢复完成!" -ForegroundColor Green
        Write-Host "📊 恢复统计:" -ForegroundColor Cyan
        Write-Host "   🔄 已恢复路径数: $($backupPaths.Count)" -ForegroundColor Green
        Write-Host "   📁 使用的备份文件: $selectedBackupFile" -ForegroundColor Blue
        Write-Host "   💾 恢复前备份: $preRestoreBackupPath" -ForegroundColor Blue
        
        Write-Host "💡 提示:" -ForegroundColor Yellow
        Write-Host "   • 恢复已生效，新打开的终端将使用恢复后的PATH" -ForegroundColor White
        Write-Host "   • 当前终端可能需要重启才能看到更改" -ForegroundColor White
    }
    catch {
        Write-Error "恢复操作失败: $_"
        exit 1
    }
}
else {
    Write-Host "❌ 用户取消操作，PATH环境变量未被修改" -ForegroundColor Yellow
    exit 0
}
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
