

<#
.SYNOPSIS
    下载AI模型脚本，支持GPU显存和系统内存检测

.DESCRIPTION
    该脚本会检测系统的GPU显存和内存情况，根据可用资源智能选择合适的模型进行下载。
    - 有GPU时：检查显存是否足够运行模型
    - 无GPU时：限制下载小于8GB的模型，使用系统内存运行
    - macOS系统：使用系统内存作为显存计算基准
    - 支持从JSON配置文件读取模型列表
    - 支持skip参数跳过指定模型

.EXAMPLE
    .\downloadModels.ps1
    运行脚本自动检测系统资源并下载合适的模型
#>

# 导入硬件检测模块和操作系统检测模块
Import-Module "$PSScriptRoot\..\psutils\index.psm1" -Force

<#
.SYNOPSIS
    从JSON配置文件加载模型列表

.DESCRIPTION
    读取models.json文件并返回模型配置数组

.OUTPUTS
    返回模型配置数组
#>
function Get-ModelListFromConfig {
    $configPath = Join-Path $PSScriptRoot "models.json"
    
    if (-not (Test-Path $configPath)) {
        Write-Error "配置文件不存在: $configPath"
        return @()
    }
    
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        return $config.models
    }
    catch {
        Write-Error "读取配置文件失败: $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    检查模型是否可以下载

.DESCRIPTION
    根据系统资源情况判断模型是否可以下载和运行

.PARAMETER Model
    要检查的模型信息

.PARAMETER GpuInfo
    GPU信息

.PARAMETER MemoryInfo
    内存信息

.OUTPUTS
    返回布尔值表示是否可以下载
#>
function Test-ModelCanDownload {
    param(
        [hashtable]$Model,
        [hashtable]$GpuInfo,
        [hashtable]$MemoryInfo
    )
    

    $modelMemoryGB = if ($Model.Size ) { $Model.Size } else { 8 }
    $modelVramGB = if ($Model.VramRequired) { $Model.VramRequired } else { 4 }
    
    if ($GpuInfo.HasGpu) {
        # 有GPU时检查显存
        if ($GpuInfo.VramGB -ge $modelVramGB) {
            Write-Host "✓ 模型 $($Model.Name) 可以使用GPU运行 (需要显存: ${modelVramGB}GB, 可用显存: $($GpuInfo.VramGB)GB)" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "✗ 模型 $($Model.Name) 显存不足 (需要显存: ${modelVramGB}GB, 可用显存: $($GpuInfo.VramGB)GB)" -ForegroundColor Red
            return $false
        }
    }
    else {
        # 无GPU时限制下载小于8GB的模型，并检查系统内存
        if ($modelMemoryGB -gt 8) {
            Write-Host "✗ 模型 $($Model.Name) 过大，无GPU时不建议下载 (模型大小: ${modelMemoryGB}GB > 8GB限制)" -ForegroundColor Red
            return $false
        }
        
        # 检查系统内存是否足够（建议至少有模型大小的1.5倍内存）
        $requiredMemory = $modelMemoryGB * 1.5
        if ($MemoryInfo.TotalGB -ge $requiredMemory) {
            Write-Host "✓ 模型 $($Model.Name) 可以使用CPU运行 (需要内存: ${modelMemoryGB}GB, 建议内存: ${requiredMemory}GB, 可用内存: $($MemoryInfo.AvailableGB)GB)" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "✗ 模型 $($Model.Name) 系统内存不足 (建议: ${requiredMemory}GB, 可用内存: $($MemoryInfo.AvailableGB)GB)" -ForegroundColor Red
            return $false
        }
    }
}

# 主程序开始
Write-Host "=== AI模型下载脚本 ===" -ForegroundColor Cyan
Write-Host "正在检测系统资源..." -ForegroundColor Yellow

# 检测操作系统
$osType = Get-OperatingSystem
Write-Host "操作系统: $osType" -ForegroundColor White

# 获取系统信息
$gpuInfo = Get-GpuInfo
$memoryInfo = Get-SystemMemoryInfo

# macOS系统特殊处理：使用系统内存作为显存计算基准
if ($osType -eq "macOS") {
    Write-Host "检测到macOS系统，使用系统内存作为显存计算基准" -ForegroundColor Yellow
    $gpuInfo.VramGB = $memoryInfo.TotalGB - 2
    $gpuInfo.HasGpu = $true  # 将macOS视为有GPU（使用统一内存架构）
}
else {
    # 其他系统最小显存按照8GB
    $gpuInfo.VramGB = [math]::max($gpuInfo.VramGB, 8)
}

# 从配置文件加载模型列表
$modelList = Get-ModelListFromConfig
if ($modelList.Count -eq 0) {
    Write-Error "无法加载模型配置，脚本退出"
    exit 1
}

# 显示系统信息
Write-Host "`n系统资源信息:" -ForegroundColor Cyan
Write-Host "GPU状态: $($gpuInfo.GpuType)" -ForegroundColor White
if ($gpuInfo.HasGpu) {
    Write-Host "显存大小: $($gpuInfo.VramGB)GB" -ForegroundColor White
}
Write-Host "系统内存: $($memoryInfo.TotalGB)GB (可用: $($memoryInfo.AvailableGB)GB)" -ForegroundColor White

# 检查并下载模型
Write-Host "`n开始检查模型..." -ForegroundColor Cyan
$downloadedCount = 0
$skippedCount = 0

foreach ($model in $modelList) {
    Write-Host "`n检查模型: $($model.name)" -ForegroundColor Yellow
    
    # 检查是否设置了skip参数
    if ($model.skip -eq $true) {
        Write-Host "⏭ 模型 $($model.name) 已设置为跳过" -ForegroundColor Gray
        $skippedCount++
        continue
    }
    
    # 转换为hashtable格式以兼容现有函数
    $modelHashtable = @{
        Name         = $model.name
        Size         = $model.size
        VramRequired = $model.vramRequired
        ModelId      = $model.modelId
    }
    
    if (Test-ModelCanDownload -Model $modelHashtable -GpuInfo $gpuInfo -MemoryInfo $memoryInfo) {
        Write-Host "正在下载模型: $($model.name)..." -ForegroundColor Cyan
        try {
            ollama pull $model.modelId
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ 模型 $($model.name) 下载成功" -ForegroundColor Green
                $downloadedCount++
            }
            else {
                Write-Host "✗ 模型 $($model.name) 下载失败" -ForegroundColor Red
                $skippedCount++
            }
        }
        catch {
            Write-Host "✗ 模型 $($model.name) 下载出错: $($_.Exception.Message)" -ForegroundColor Red
            $skippedCount++
        }
    }
    else {
        Write-Host "跳过模型: $($model.name)" -ForegroundColor Yellow
        $skippedCount++
    }
}

# 显示总结
Write-Host "`n=== 下载完成 ===" -ForegroundColor Cyan
Write-Host "成功下载: $downloadedCount 个模型" -ForegroundColor Green
Write-Host "跳过模型: $skippedCount 个模型" -ForegroundColor Yellow

if ($downloadedCount -eq 0) {
    Write-Host "`n建议:" -ForegroundColor Yellow
    if (-not $gpuInfo.HasGpu) {
        Write-Host "- 考虑升级显卡以支持更大的模型" -ForegroundColor White
        Write-Host "- 或增加系统内存以运行更多CPU模型" -ForegroundColor White
    }
    else {
        Write-Host "- 考虑升级显卡显存以支持更大的模型" -ForegroundColor White
    }
}