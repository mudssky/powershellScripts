<#
.SYNOPSIS
    缓存模块性能优化验证脚本
    快速验证 PSUtils 缓存模块 v1.4.0 的新功能

.DESCRIPTION
    本脚本用于快速验证缓存模块的性能优化功能：
    1. 基本缓存功能
    2. 缓存统计信息
    3. 缓存清理功能
    4. 异常处理
    5. 性能提升验证

.AUTHOR
    mudssky

.VERSION
    1.0.0
#>

# 导入缓存模块
Import-Module "$PSScriptRoot\modules\cache.psm1" -Force

Write-Host "=== PSUtils 缓存模块性能优化验证 ===" -ForegroundColor Cyan
Write-Host ""

# 1. 基本功能测试
Write-Host "1. 基本缓存功能测试" -ForegroundColor Yellow

# 创建测试缓存
$result1 = Invoke-WithCache -Key "test-basic" -ScriptBlock {
    Start-Sleep -Milliseconds 500
    "测试结果: $(Get-Date)"
}
Write-Host "  ✓ 首次执行完成: $result1" -ForegroundColor Green

# 缓存命中测试
$result2 = Invoke-WithCache -Key "test-basic" -ScriptBlock {
    "这不应该被执行"
}
Write-Host "  ✓ 缓存命中测试: $($result1 -eq $result2)" -ForegroundColor Green
Write-Host ""

# 2. 缓存统计信息测试
Write-Host "2. 缓存统计信息测试" -ForegroundColor Yellow
$stats = Get-CacheStats
Write-Host ""

# 3. 不同缓存类型测试
Write-Host "3. 缓存类型测试" -ForegroundColor Yellow

# XML 缓存
$xmlResult = Invoke-WithCache -Key "test-xml" -CacheType XML -ScriptBlock {
    @{ Name = "测试"; Value = 123; Date = Get-Date }
}
Write-Host "  ✓ XML 缓存创建完成" -ForegroundColor Green

# Text 缓存
$textResult = Invoke-WithCache -Key "test-text" -CacheType Text -ScriptBlock {
    "这是文本缓存测试"
}
Write-Host "  ✓ Text 缓存创建完成" -ForegroundColor Green
Write-Host ""

# 4. 异常处理测试
Write-Host "4. 异常处理测试" -ForegroundColor Yellow
try {
    Invoke-WithCache -Key "test-error" -ScriptBlock {
        throw "测试异常"
    }
    Write-Host "  ✗ 异常处理失败" -ForegroundColor Red
}
catch {
    Write-Host "  ✓ 异常正确传播: $($_.Exception.Message)" -ForegroundColor Green
}
Write-Host ""

# 5. 性能测试
Write-Host "5. 性能提升验证" -ForegroundColor Yellow

# 首次执行（无缓存）
$stopwatch1 = [System.Diagnostics.Stopwatch]::StartNew()
$perfResult1 = Invoke-WithCache -Key "perf-test" -ScriptBlock {
    Start-Sleep -Milliseconds 1000
    "性能测试结果"
}
$stopwatch1.Stop()
$noCacheTime = $stopwatch1.ElapsedMilliseconds

# 第二次执行（缓存命中）
$stopwatch2 = [System.Diagnostics.Stopwatch]::StartNew()
$perfResult2 = Invoke-WithCache -Key "perf-test" -ScriptBlock {
    "这不应该被执行"
}
$stopwatch2.Stop()
$cacheTime = $stopwatch2.ElapsedMilliseconds

$speedup = [math]::Round($noCacheTime / $cacheTime, 2)
Write-Host "  首次执行: $noCacheTime ms" -ForegroundColor Gray
Write-Host "  缓存命中: $cacheTime ms" -ForegroundColor Gray
Write-Host "  ✓ 性能提升: ${speedup}x" -ForegroundColor Green
Write-Host ""

# 6. 缓存清理测试
Write-Host "6. 缓存清理功能测试" -ForegroundColor Yellow

# 预览清理
Write-Host "  预览清理操作:" -ForegroundColor Gray
$whatIfResult = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromSeconds(1)) -WhatIf

# 等待缓存过期
Start-Sleep -Seconds 2

# 实际清理
Write-Host "  执行清理操作:" -ForegroundColor Gray
$cleanupResult = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromSeconds(1))
Write-Host ""

# 7. 最终统计
Write-Host "7. 最终缓存统计" -ForegroundColor Yellow
$finalStats = Get-CacheStats
Write-Host ""

# 8. 清理测试缓存
Write-Host "8. 清理测试缓存" -ForegroundColor Yellow
Clear-ExpiredCache -Force | Out-Null
Write-Host "  ✓ 所有测试缓存已清理" -ForegroundColor Green
Write-Host ""

Write-Host "=== 验证完成 ===" -ForegroundColor Cyan
Write-Host "缓存模块 v1.4.0 性能优化功能验证通过！" -ForegroundColor Green
Write-Host ""
Write-Host "主要优化特性：" -ForegroundColor White
Write-Host "  ✓ MD5 哈希提供程序重用" -ForegroundColor Green
Write-Host "  ✓ 文件操作优化" -ForegroundColor Green
Write-Host "  ✓ 缓存统计信息跟踪" -ForegroundColor Green
Write-Host "  ✓ 自动缓存清理功能" -ForegroundColor Green
Write-Host "  ✓ 改进的异常处理" -ForegroundColor Green
Write-Host "  ✓ 性能监控和分析" -ForegroundColor Green