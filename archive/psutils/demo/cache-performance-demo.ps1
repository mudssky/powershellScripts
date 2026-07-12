<#
.SYNOPSIS
    缓存性能优化演示脚本
    展示 PSUtils 缓存模块 v1.4.0 的性能优化功能

.DESCRIPTION
    本脚本演示缓存模块的以下新功能：
    1. 缓存统计信息跟踪
    2. 自动缓存清理功能
    3. 性能监控和分析
    4. 错误处理和恢复机制

.AUTHOR
    mudssky

.VERSION
    1.0.0
#>

# 导入缓存模块
Import-Module "$PSScriptRoot\psutils\modules\cache.psm1" -Force

Write-Host "=== PSUtils 缓存模块性能优化演示 v1.4.0 ===" -ForegroundColor Cyan
Write-Host ""

# 1. 演示基本缓存功能和统计信息
Write-Host "1. 基本缓存功能演示" -ForegroundColor Yellow
Write-Host "执行一些缓存操作来生成统计数据..." -ForegroundColor Gray

# 创建一些测试缓存
$testKeys = @(
    "performance-test-1",
    "performance-test-2", 
    "performance-test-3",
    "performance-test-xml",
    "performance-test-text"
)

foreach ($key in $testKeys) {
    $cacheType = if ($key -like "*text*") { "Text" } else { "XML" }
    
    # 第一次调用（缓存未命中）
    $result1 = Invoke-WithCache -Key $key -CacheType $cacheType -ScriptBlock {
        Start-Sleep -Milliseconds 100  # 模拟耗时操作
        if ($key -like "*text*") {
            "这是文本缓存测试数据 - $(Get-Date)"
        }
        else {
            @{
                Timestamp    = Get-Date
                ProcessCount = (Get-Process).Count
                Key          = $key
            }
        }
    }
    
    # 第二次调用（缓存命中）
    $result2 = Invoke-WithCache -Key $key -CacheType $cacheType -ScriptBlock {
        Start-Sleep -Milliseconds 100
        "这不应该被执行"
    }
    
    Write-Host "  ✓ 缓存键 '$key' ($cacheType) 已创建" -ForegroundColor Green
}

Write-Host ""

# 2. 显示缓存统计信息
Write-Host "2. 缓存统计信息" -ForegroundColor Yellow
$stats = Get-CacheStats
Write-Host ""

# 3. 演示详细统计信息
Write-Host "3. 详细缓存信息" -ForegroundColor Yellow
$detailedStats = Get-CacheStats -Detailed
Write-Host ""

# 4. 演示缓存清理功能
Write-Host "4. 缓存清理功能演示" -ForegroundColor Yellow

# 预览清理操作
Write-Host "预览清理操作（WhatIf模式）：" -ForegroundColor Gray
$whatIfResult = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromSeconds(1)) -WhatIf
Write-Host ""

# 等待一秒让缓存"过期"
Write-Host "等待缓存过期..." -ForegroundColor Gray
Start-Sleep -Seconds 2

# 实际清理过期缓存
Write-Host "清理过期缓存：" -ForegroundColor Gray
$cleanupResult = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromSeconds(1))
Write-Host ""

# 5. 显示清理后的统计信息
Write-Host "5. 清理后的缓存统计" -ForegroundColor Yellow
$finalStats = Get-CacheStats
Write-Host ""

# 6. 演示强制清理所有缓存
Write-Host "6. 强制清理所有缓存" -ForegroundColor Yellow

# 重新创建一些缓存用于演示
Invoke-WithCache -Key "cleanup-demo" -ScriptBlock { "演示数据" } | Out-Null

Write-Host "强制清理所有缓存文件：" -ForegroundColor Gray
$forceCleanup = Clear-ExpiredCache -Force
Write-Host ""

# 7. 性能对比演示
Write-Host "7. 性能对比演示" -ForegroundColor Yellow
Write-Host "比较缓存命中与未命中的性能差异..." -ForegroundColor Gray

# 测试缓存性能
$performanceKey = "performance-benchmark"

# 第一次执行（无缓存）
$stopwatch1 = [System.Diagnostics.Stopwatch]::StartNew()
$result = Invoke-WithCache -Key $performanceKey -ScriptBlock {
    Start-Sleep -Milliseconds 500  # 模拟耗时操作
    Get-Process | Select-Object -First 10
}
$stopwatch1.Stop()
$noCacheTime = $stopwatch1.ElapsedMilliseconds

# 第二次执行（有缓存）
$stopwatch2 = [System.Diagnostics.Stopwatch]::StartNew()
$cachedResult = Invoke-WithCache -Key $performanceKey -ScriptBlock {
    Start-Sleep -Milliseconds 500
    "这不应该被执行"
}
$stopwatch2.Stop()
$cacheTime = $stopwatch2.ElapsedMilliseconds

$speedup = [math]::Round($noCacheTime / $cacheTime, 2)
Write-Host "  无缓存执行时间: $noCacheTime ms" -ForegroundColor Red
Write-Host "  缓存命中时间: $cacheTime ms" -ForegroundColor Green
Write-Host "  性能提升: ${speedup}x" -ForegroundColor Cyan
Write-Host ""

# 8. 最终统计信息
Write-Host "8. 最终缓存统计" -ForegroundColor Yellow
$finalStats = Get-CacheStats
Write-Host ""

# 9. 清理演示缓存
Write-Host "9. 清理演示缓存" -ForegroundColor Yellow
Clear-ExpiredCache -Force | Out-Null
Write-Host "所有演示缓存已清理完成" -ForegroundColor Green
Write-Host ""

Write-Host "=== 演示完成 ===" -ForegroundColor Cyan
Write-Host "缓存模块 v1.4.0 的主要性能优化：" -ForegroundColor White
Write-Host "  ✓ 重用MD5哈希提供程序" -ForegroundColor Green
Write-Host "  ✓ 优化文件操作" -ForegroundColor Green
Write-Host "  ✓ 缓存统计信息跟踪" -ForegroundColor Green
Write-Host "  ✓ 自动缓存清理功能" -ForegroundColor Green
Write-Host "  ✓ 改进错误处理" -ForegroundColor Green
Write-Host "  ✓ 性能监控和分析" -ForegroundColor Green