#!/usr/bin/env pwsh

<#
.SYNOPSIS
    清理环境变量中无用的路径，移除不存在或没有可执行文件的路径。支持交互式筛选、备份恢复及智能缩短路径。
.DESCRIPTION
    此脚本会扫描指定环境变量目标（Machine或User）的PATH环境变量，
    识别并移除以下类型的无效路径：
    1. 不存在的目录路径
    2. 存在但不包含任何可执行文件（.exe, .cmd, .bat, .ps1）的目录
    3. 重复的路径项
    4. User PATH中与System PATH重复的路径项（仅在清理User级别时）
    
    新增功能：
    - 智能缩短：自动将路径替换为环境变量（如 %USERPROFILE%）
    - 交互式筛选：通过图形界面手动选择要保留的路径
    - 备份恢复：支持从备份文件恢复环境变量
    - 路径规范化：统一移除路径末尾的斜杠
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
.PARAMETER RestoreFrom
    [新功能] 指定备份文件路径，直接从该文件恢复环境变量（将覆盖当前设置）
.PARAMETER Interactive
    [新功能] 启用交互式模式，使用图形界面(GridView)手动选择要保留的路径
.NOTES
    - 建议在执行前备份当前的PATH环境变量
    - 清理Machine级别的环境变量需要管理员权限
    - 脚本会自动创建备份文件以便恢复
.EXAMPLE
    .\cleanEnvPath.ps1
    使用默认设置清理当前用户的PATH环境变量
.EXAMPLE
    .\cleanEnvPath.ps1 -Interactive
    启用交互式界面手动筛选路径
.EXAMPLE
    .\cleanEnvPath.ps1 -RestoreFrom ".\backup\PATH_User_20231201.txt"
    从指定备份文件恢复环境变量
#>


[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [ValidateSet('Machine', 'User')]
    [string]$EnvTarget = 'User',
    
    [switch]$Force,
    
    [string]$BackupPath = (Join-Path $PSScriptRoot "backup"),
    
    [switch]$SkipSystemPathCheck,

    [string]$RestoreFrom = "",

    [switch]$Interactive
)

# -------------------------------------------------------------------------
# 辅助函数：智能缩短路径
# -------------------------------------------------------------------------
function Optimize-PathString {
    param ([string]$PathString)
    # 定义常见的替换映射
    $replacements = @{
        [Environment]::GetEnvironmentVariable('USERPROFILE')       = '%USERPROFILE%'
        [Environment]::GetEnvironmentVariable('ProgramFiles')      = '%ProgramFiles%'
        [Environment]::GetEnvironmentVariable('ProgramFiles(x86)') = '%ProgramFiles(x86)%'
        [Environment]::GetEnvironmentVariable('SystemRoot')        = '%SystemRoot%'
        # 可以根据需要添加更多，例如 JAVA_HOME 等
    }

    foreach ($key in $replacements.Keys) {
        if ($PathString -and $PathString.StartsWith($key, [StringComparison]::OrdinalIgnoreCase)) {
            $newPath = $PathString.Replace($key, $replacements[$key])
            # 只有当替换后确实变短了才应用
            if ($newPath.Length -lt $PathString.Length) {
                return $newPath
            }
        }
    }
    return $PathString
}

# -------------------------------------------------------------------------
# 1. 恢复模式 (Restore Mode)
# -------------------------------------------------------------------------
if ($RestoreFrom) {
    if (-not (Test-Path $RestoreFrom)) { 
        Write-Error "找不到备份文件: $RestoreFrom"
        exit 1 
    }
    
    $backupContent = Get-Content $RestoreFrom -Raw
    if ($null -eq $backupContent) {
        Write-Error "备份文件为空"
        exit 1
    }
    $backupContent = $backupContent.Trim()
    
    Write-Warning "即将从文件 $RestoreFrom 恢复 $EnvTarget 环境变量！"
    if ($PSCmdlet.ShouldProcess("$EnvTarget 级别的PATH环境变量", "恢复为备份内容")) {
        try {
            Set-EnvPath -EnvTarget $EnvTarget -PathStr $backupContent
            Write-Host "✅ 已成功恢复环境变量。" -ForegroundColor Green
        }
        catch {
            Write-Error "恢复失败: $_"
            exit 1
        }
    }
    exit 0
}

# -------------------------------------------------------------------------
# 常规清理流程
# -------------------------------------------------------------------------

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

# -------------------------------------------------------------------------
# 2. 交互式筛选 (Interactive Selection)
# -------------------------------------------------------------------------
if ($Interactive) {
    Write-Host "`n🖥️  进入交互模式，请在弹出的窗口中选择要【保留】的路径..." -ForegroundColor Cyan
    
    $allPathsObj = @()
    $validPaths | ForEach-Object { $allPathsObj += [PSCustomObject]@{ Path = $_; Status = '✅ 有效'; Keep = $true } }
    $invalidPaths | ForEach-Object { $allPathsObj += [PSCustomObject]@{ Path = $_; Status = '❌ 无效'; Keep = $false } }
    $duplicatePaths | ForEach-Object { $allPathsObj += [PSCustomObject]@{ Path = $_; Status = '🔄 重复'; Keep = $false } }
    $systemDuplicatePaths | ForEach-Object { $allPathsObj += [PSCustomObject]@{ Path = $_; Status = '🔗 System重复'; Keep = $false } }

    # 弹出窗口
    $selected = $allPathsObj | Out-GridView -Title "按住Ctrl多选要保留的路径，按确定继续" -PassThru
    
    if ($selected) {
        $validPaths = $selected.Path
        # 重置其他列表，因为用户已经做出了最终选择
        $invalidPaths = @()
        $duplicatePaths = @()
        $systemDuplicatePaths = @()
        Write-Host "已根据交互式选择更新保留列表。" -ForegroundColor Green
    }
    else {
        Write-Warning "未选择任何路径，取消操作"
        exit 0
    }
}

# 显示分析结果
Write-Host "`n📊 最终处理预览:" -ForegroundColor Cyan
if (-not $Interactive) {
    Write-Host "   ✅ 有效路径: $($validPaths.Count)" -ForegroundColor Green
    Write-Host "   ❌ 无效路径: $($invalidPaths.Count)" -ForegroundColor Red
    Write-Host "   🔄 重复路径: $($duplicatePaths.Count)" -ForegroundColor Yellow
    if ($EnvTarget -eq 'User' -and -not $SkipSystemPathCheck) {
        Write-Host "   🔗 与System重复: $($systemDuplicatePaths.Count)" -ForegroundColor Magenta
    }
}
else {
    Write-Host "   ✅ 用户选择保留: $($validPaths.Count)" -ForegroundColor Green
}

$totalProblemsCount = $invalidPaths.Count + $duplicatePaths.Count + $systemDuplicatePaths.Count
if ($totalProblemsCount -eq 0 -and -not $Interactive) {
    Write-Host "`n🎉 PATH环境变量已经是最优状态，无需清理!" -ForegroundColor Green
    exit 0
}

# 显示详细信息 (非交互模式下，或交互模式下仅显示保留的)
if (-not $Interactive) {
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
}

if ($validPaths.Count -gt 0) {
    Write-Host "`n✅ 将保留的有效路径 (应用优化前):" -ForegroundColor Green
    $validPaths | ForEach-Object { Write-Host "   $_" -ForegroundColor Green }
}

# 用户确认和执行
$shouldProceed = $false

if ($PSCmdlet.ShouldProcess("$EnvTarget 级别的PATH环境变量", "更新路径设置")) {
    if ($Force) {
        $shouldProceed = $true
        Write-Host "`n⚡ 使用 -Force 参数，跳过确认直接执行" -ForegroundColor Yellow
    }
    else {
        # 显示操作摘要
        Write-Host "`n📝 操作摘要:" -ForegroundColor Cyan
        Write-Host "   🎯 目标: $EnvTarget 级别PATH环境变量" -ForegroundColor White
        Write-Host "   📁 备份位置: $backupFilePath" -ForegroundColor White
        if (-not $Interactive) {
            Write-Host "   🗑️  将移除: $($invalidPaths.Count + $duplicatePaths.Count + $systemDuplicatePaths.Count) 个路径" -ForegroundColor White
        }
        Write-Host "   ✅ 将保留: $($validPaths.Count) 个路径" -ForegroundColor White
        
        $title = "🔧 PATH环境变量清理确认"
        $message = "是否继续执行清理操作？此操作将修改 $EnvTarget 级别的PATH环境变量。"
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "确认执行"
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "取消操作"
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
        $result = $host.UI.PromptForChoice($title, $message, $options, 1)  # 默认选中No，更安全
        
        $shouldProceed = ($result -eq 0)
    }
}

if ($shouldProceed) {
    Write-Host "`n🚀 开始执行清理和优化..." -ForegroundColor Green
    
    try {
        # -------------------------------------------------------------------------
        # 3 & 4. 路径规范化 与 智能缩短 (Normalization & Smart Shortening)
        # -------------------------------------------------------------------------
        $optimizedPaths = $validPaths | ForEach-Object {
            # 4. 规范化: 移除尾部斜杠 (保留根目录如 C:\)
            $p = $_.Trim()
            if ($p -notmatch '^[a-zA-Z]:\\$') { 
                $p = $p.TrimEnd('\')
            }
            
            # 3. 智能缩短
            Optimize-PathString $p
        }

        # 构建最终的PATH字符串
        $finalPathStr = ($optimizedPaths -join ';')
        
        Write-Verbose "最终PATH内容: $finalPathStr"
        Write-Host "📝 正在更新 $EnvTarget 级别的PATH环境变量..." -ForegroundColor Cyan
        
        # 设置新的PATH环境变量
        Set-EnvPath -EnvTarget $EnvTarget -PathStr $finalPathStr
        
        # 显示成功信息
        Write-Host "`n🎉 PATH环境变量更新完成!" -ForegroundColor Green
        Write-Host "📊 统计:" -ForegroundColor Cyan
        Write-Host "   ✅ 最终路径数量: $($optimizedPaths.Count)" -ForegroundColor Green
        
        # 显示优化前后的长度对比
        $oldLen = $currentPathStr.Length
        $newLen = $finalPathStr.Length
        Write-Host "   📏 字符长度: $oldLen -> $newLen (减少了 $($oldLen - $newLen) 字符)" -ForegroundColor Yellow
        
        Write-Host "   💾 备份文件: $backupFilePath" -ForegroundColor Blue
        
        # 提示重启或重新加载
        Write-Host "`n💡 提示:" -ForegroundColor Yellow
        Write-Host "   • 更改已生效，新打开的终端将使用更新后的PATH" -ForegroundColor White
        Write-Host "   • 当前终端可能需要重启才能看到更改" -ForegroundColor White
        Write-Host "   • 如需恢复，请使用备份文件: $backupFilePath" -ForegroundColor White
    }
    catch {
        Write-Error "操作失败: $_"
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
