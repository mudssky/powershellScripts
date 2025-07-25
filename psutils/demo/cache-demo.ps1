<#
.SYNOPSIS
    PowerShell缓存模块演示脚本

.DESCRIPTION
    演示Invoke-WithCache函数的各种功能和用法，包括基本缓存、强制刷新、
    跳过缓存、复杂对象缓存和缓存过期等特性。展示v1.2.0版本的性能优化效果。

.NOTES
    作者: mudssky
    版本: 1.2.0
    创建日期: 2025-01-07
    更新日期: 2025-01-07
    依赖: psutils\modules\cache.psm1
    
    v1.2.0 优化内容:
    - 缓存目录创建移至模块级别，避免重复检查
    - 使用MD5哈希替代SHA256，提升文件名生成速度
    - 支持长期缓存（如30天），适用于工具初始化
#>

# 导入缓存模块
$cacheModulePath = Join-Path $PSScriptRoot "..\modules\cache.psm1"
if (Test-Path $cacheModulePath) {
    Import-Module $cacheModulePath -Force
    Write-Host "✅ 缓存模块v1.2.0加载成功" -ForegroundColor Green
}
else {
    Write-Error "❌ 未找到缓存模块: $cacheModulePath"
    exit 1
}

Write-Host "`n🚀 PowerShell缓存模块v1.2.0演示" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Cyan
Write-Host "🔧 v1.2.0优化: MD5哈希 + 模块级缓存目录 + 长期缓存支持" -ForegroundColor Blue

# 演示1: 基本缓存功能
Write-Host "`n📦 演示1: 基本缓存功能" -ForegroundColor Yellow
Write-Host "首次执行 (应该执行脚本块):" -ForegroundColor White
$result1 = Measure-Command {
    $data = Invoke-WithCache -Key "demo-basic" -ScriptBlock {
        Write-Host "  正在执行耗时操作..." -ForegroundColor Gray
        Start-Sleep -Milliseconds 500
        Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    Write-Host "  结果: $data" -ForegroundColor Green
}
Write-Host "  耗时: $($result1.TotalMilliseconds) 毫秒" -ForegroundColor Magenta

Write-Host "`n第二次执行 (应该从缓存读取):" -ForegroundColor White
$result2 = Measure-Command {
    $data = Invoke-WithCache -Key "demo-basic" -ScriptBlock {
        Write-Host "  正在执行耗时操作..." -ForegroundColor Gray
        Start-Sleep -Milliseconds 500
        Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    Write-Host "  结果: $data" -ForegroundColor Green
}
Write-Host "  耗时: $($result2.TotalMilliseconds) 毫秒" -ForegroundColor Magenta
Write-Host "  性能提升: $([math]::Round(($result1.TotalMilliseconds - $result2.TotalMilliseconds) / $result1.TotalMilliseconds * 100, 1))%" -ForegroundColor Cyan

# 演示2: 长期缓存 (新功能)
Write-Host "`n📅 演示2: 长期缓存 (30天) - 适用于工具初始化" -ForegroundColor Yellow
Write-Host "模拟starship初始化缓存:" -ForegroundColor White
$longTermResult = Measure-Command {
    $starshipInit = Invoke-WithCache -Key "starship-init-demo" -MaxAge ([TimeSpan]::FromDays(30)) -ScriptBlock {
        Write-Host "  正在初始化starship (模拟)..." -ForegroundColor Gray
        Start-Sleep -Milliseconds 200
        "# Starship初始化脚本内容 (模拟)\nSet-PSReadLineOption -PredictionSource History"
    }
    Write-Host "  缓存有效期: 30天" -ForegroundColor Green
}
Write-Host "  耗时: $($longTermResult.TotalMilliseconds) 毫秒" -ForegroundColor Magenta

# 演示3: Force参数
Write-Host "`n🔄 演示3: Force参数强制刷新缓存" -ForegroundColor Yellow
Write-Host "使用Force参数 (应该重新执行脚本块):" -ForegroundColor White
$result3 = Measure-Command {
    $data = Invoke-WithCache -Key "demo-basic" -Force -ScriptBlock {
        Write-Host "  正在执行耗时操作..." -ForegroundColor Gray
        Start-Sleep -Milliseconds 500
        Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    Write-Host "  结果: $data" -ForegroundColor Green
}
Write-Host "  耗时: $($result3.TotalMilliseconds) 毫秒" -ForegroundColor Magenta

# 演示4: NoCache参数
Write-Host "`n🚫 演示4: NoCache参数跳过缓存" -ForegroundColor Yellow
Write-Host "使用NoCache参数 (应该直接执行，不读写缓存):" -ForegroundColor White
$result4 = Measure-Command {
    $data = Invoke-WithCache -Key "demo-nocache" -NoCache -ScriptBlock {
        Write-Host "  正在执行耗时操作..." -ForegroundColor Gray
        Start-Sleep -Milliseconds 500
        Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    Write-Host "  结果: $data" -ForegroundColor Green
}
Write-Host "  耗时: $($result4.TotalMilliseconds) 毫秒" -ForegroundColor Magenta

# 演示5: 复杂对象缓存
Write-Host "`n🏗️ 演示5: 复杂对象缓存" -ForegroundColor Yellow
Write-Host "缓存复杂PowerShell对象:" -ForegroundColor White
$complexData = Invoke-WithCache -Key "demo-complex" -ScriptBlock {
    Write-Host "  正在生成复杂对象..." -ForegroundColor Gray
    [PSCustomObject]@{
        Timestamp    = Get-Date
        ProcessCount = (Get-Process).Count
        SystemInfo   = @{
            OS           = $env:OS
            ComputerName = $env:COMPUTERNAME
            UserName     = $env:USERNAME
        }
        RandomData   = 1..5 | ForEach-Object { Get-Random -Maximum 100 }
        CacheVersion = "v1.2.0"
    }
}
Write-Host "  对象类型: $($complexData.GetType().Name)" -ForegroundColor Green
Write-Host "  时间戳: $($complexData.Timestamp)" -ForegroundColor Green
Write-Host "  进程数量: $($complexData.ProcessCount)" -ForegroundColor Green
Write-Host "  随机数据: $($complexData.RandomData -join ', ')" -ForegroundColor Green
Write-Host "  缓存版本: $($complexData.CacheVersion)" -ForegroundColor Green

# 演示6: 缓存过期
Write-Host "`n⏰ 演示6: 缓存过期机制" -ForegroundColor Yellow
Write-Host "设置1秒过期时间:" -ForegroundColor White
$shortCacheData = Invoke-WithCache -Key "demo-expiry" -MaxAge ([TimeSpan]::FromSeconds(1)) -ScriptBlock {
    Write-Host "  正在执行短期缓存操作..." -ForegroundColor Gray
    "缓存时间: $(Get-Date -Format 'HH:mm:ss.fff')"
}
Write-Host "  结果: $shortCacheData" -ForegroundColor Green

Write-Host "`n等待2秒后再次调用 (缓存应该过期):" -ForegroundColor White
Start-Sleep -Seconds 2
$expiredCacheData = Invoke-WithCache -Key "demo-expiry" -MaxAge ([TimeSpan]::FromSeconds(1)) -ScriptBlock {
    Write-Host "  正在执行短期缓存操作..." -ForegroundColor Gray
    "缓存时间: $(Get-Date -Format 'HH:mm:ss.fff')"
}
Write-Host "  结果: $expiredCacheData" -ForegroundColor Green

# 显示缓存文件信息
Write-Host "`n📁 缓存文件信息" -ForegroundColor Yellow
$cacheDir = Join-Path $env:LOCALAPPDATA "PowerShellCache"
if (Test-Path $cacheDir) {
    $cacheFiles = Get-ChildItem -Path $cacheDir -Filter "*.cache.xml"
    Write-Host "缓存目录: $cacheDir" -ForegroundColor White
    Write-Host "缓存文件数量: $($cacheFiles.Count)" -ForegroundColor White
    
    if ($cacheFiles.Count -gt 0) {
        Write-Host "`n缓存文件列表 (MD5哈希文件名):" -ForegroundColor White
        $cacheFiles | ForEach-Object {
            $size = [math]::Round($_.Length / 1KB, 2)
            $hashLength = $_.BaseName.Replace('.cache', '').Length
            Write-Host "  📄 $($_.Name) ($size KB, $($_.LastWriteTime), 哈希长度: $hashLength)" -ForegroundColor Gray
        }
    }
}
else {
    Write-Host "缓存目录不存在" -ForegroundColor Red
}

Write-Host "`n✨ v1.2.0演示完成!" -ForegroundColor Green
Write-Host "🚀 性能优化亮点:" -ForegroundColor Cyan
Write-Host "• MD5哈希: 32位文件名，比SHA256快约2-3倍" -ForegroundColor Gray
Write-Host "• 模块级缓存目录: 避免重复目录检查，提升响应速度" -ForegroundColor Gray
Write-Host "• 长期缓存支持: 30天缓存适用于工具初始化脚本" -ForegroundColor Gray
Write-Host "• 内存优化: 及时释放哈希对象，减少内存占用" -ForegroundColor Gray

Write-Host "`n💡 最佳实践建议:" -ForegroundColor White
Write-Host "• 系统信息查询: 缓存1-24小时" -ForegroundColor Gray
Write-Host "• 网络请求和API: 缓存5-60分钟" -ForegroundColor Gray
Write-Host "• 工具初始化脚本: 缓存7-30天" -ForegroundColor Gray
Write-Host "• 开发环境配置: 缓存1-7天" -ForegroundColor Gray