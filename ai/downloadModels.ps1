

<#
.SYNOPSIS
    下载AI模型脚本，支持GPU显存和系统内存检测

.DESCRIPTION
    该脚本会检测系统的GPU显存和内存情况，根据可用资源智能选择合适的模型进行下载。
    - 有GPU时：检查显存是否足够运行模型
    - 无GPU时：限制下载小于8GB的模型，使用系统内存运行

.EXAMPLE
    .\downloadModels.ps1
    运行脚本自动检测系统资源并下载合适的模型
#>

# 导入硬件检测模块
Import-Module "$PSScriptRoot\..\psutils\index.psm1" -Force

# 模型列表，包含内存和显存需求信息（单位：GB）
$modelList = @(
    @{
        ModelId = "bge-m3"
        Name    = 'bge-m3'
        Size = 2
        VramRequired = 2
    },
    @{
        ModelId = "qwen3:8b"
        Name    = 'qwen3:8b'
        Size = 8
        VramRequired = 8
    },
    @{
        ModelId = "gemma3:4b"
        Name    = 'gemma3:4b'
        Size = 4
        VramRequired = 4
    },
    @{
        ModelId = "gemma3n:e4b"
        Name    = 'gemma3n:e4b'
        Size = 4
        VramRequired = 4
    },
    # @{
    #     ModelId = "deepseek-r1"
    #     Name    = 'deepseek-r1'
    #     Size = 7
    #     VramRequired = 7
    # },
    @{
        ModelId = "qwen3:30b-a3b"
        Name    = 'qwen3:30b-a3b'
        Size = 19
        VramRequired = 16
    }
)

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
    

    $modelMemoryGB = $Model.Size 
    $modelVramGB = $Model.VramRequired
    
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

# 获取系统信息
$gpuInfo = Get-GpuInfo
$memoryInfo = Get-SystemMemoryInfo

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
    Write-Host "`n检查模型: $($model.Name)" -ForegroundColor Yellow
    
    if (Test-ModelCanDownload -Model $model -GpuInfo $gpuInfo -MemoryInfo $memoryInfo) {
        Write-Host "正在下载模型: $($model.Name)..." -ForegroundColor Cyan
        try {
            ollama pull $model.ModelId
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ 模型 $($model.Name) 下载成功" -ForegroundColor Green
                $downloadedCount++
            }
            else {
                Write-Host "✗ 模型 $($model.Name) 下载失败" -ForegroundColor Red
                $skippedCount++
            }
        }
        catch {
            Write-Host "✗ 模型 $($model.Name) 下载出错: $($_.Exception.Message)" -ForegroundColor Red
            $skippedCount++
        }
    }
    else {
        Write-Host "跳过模型: $($model.Name)" -ForegroundColor Yellow
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