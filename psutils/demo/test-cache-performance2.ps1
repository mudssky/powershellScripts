<#
.SYNOPSIS
    测试 Invoke-WithCache 性能提升效果
    
.DESCRIPTION
    本脚本用于测试 PSUtils 缓存模块在实际使用场景中的性能提升效果，
    特别是针对 starship 和 zoxide 初始化等耗时操作。
    
.AUTHOR
    mudssky
    
.VERSION
    1.0.0
#>

# 导入缓存模块
Import-Module "$PSScriptRoot\psutils\modules\cache.psm1" -Force

Write-Host "=== Invoke-WithCache 性能测试 ===" -ForegroundColor Cyan
Write-Host ""

# 清理之前的测试缓存
Write-Host "清理测试缓存..." -ForegroundColor Yellow
Clear-ExpiredCache -Force | Out-Null

# 测试函数：模拟 starship 初始化
function Test-StarshipInit {
    param(
        [switch]$UseCache
    )
    
    if ($UseCache) {
        return Invoke-WithCache -Key "test-starship-init" -MaxAge ([TimeSpan]::FromDays(30)) -ScriptBlock {
            # 模拟 starship init powershell 的耗时操作
            Start-Sleep -Milliseconds 800
            "# Starship prompt configuration`nInvoke-Expression (&starship init powershell)"
        }
    } else {
        # 直接执行，不使用缓存
        Start-Sleep -Milliseconds 800
        return "# Starship prompt configuration`nInvoke-Expression (&starship init powershell)"
    }
}

# 测试函数：模拟 zoxide 初始化
function Test-ZoxideInit {
    param(
        [switch]$UseCache
    )
    
    if ($UseCache) {
        return Invoke-WithCache -Key "test-zoxide-init" -MaxAge ([TimeSpan]::FromDays(30)) -ScriptBlock {
            # 模拟 zoxide init powershell 的耗时操作
            Start-Sleep -Milliseconds 600
            "# Zoxide directory navigation`nSet-Alias z __zoxide_z"
        }
    } else {
        # 直接执行，不使用缓存
        Start-Sleep -Milliseconds 600
        return "# Zoxide directory navigation`nSet-Alias z __zoxide_z"
    }
}

# 测试函数：模拟复杂配置加载
function Test-ComplexConfig {
    param(
        [switch]$UseCache
    )
    
    if ($UseCache) {
        return Invoke-WithCache -Key "test-complex-config" -MaxAge ([TimeSpan]::FromHours(1)) -ScriptBlock {
            # 模拟复杂配置处理
            Start-Sleep -Milliseconds 1200
            @{
                Modules = @('PSReadLine', 'posh-git', 'Terminal-Icons')
                Settings = @{
                    Theme = 'Dark'
                    Font = 'Cascadia Code'
                    Size = 12
                }
                Timestamp = Get-Date
            }
        }
    } else {
        # 直接执行，不使用缓存
        Start-Sleep -Milliseconds 1200
        return @{
            Modules = @('PSReadLine', 'posh-git', 'Terminal-Icons')
            Settings = @{
                Theme = 'Dark'
                Font = 'Cascadia Code'
                Size = 12
            }
            Timestamp = Get-Date
        }
    }
}

# 性能测试函数
function Measure-Performance {
    param(
        [string]$TestName,
        [scriptblock]$TestScript,
        [int]$Iterations = 3
    )
    
    $times = @()
    
    for ($i = 1; $i -le $Iterations; $i++) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = & $TestScript
        $stopwatch.Stop()
        $times += $stopwatch.ElapsedMilliseconds
        
        if ($i -eq 1) {
            Write-Host "    第 $i 次: $($stopwatch.ElapsedMilliseconds) ms" -ForegroundColor Gray
        } else {
            Write-Host "    第 $i 次: $($stopwatch.ElapsedMilliseconds) ms" -ForegroundColor Green
        }
    }
    
    $avgTime = ($times | Measure-Object -Average).Average
    $minTime = ($times | Measure-Object -Minimum).Minimum
    $maxTime = ($times | Measure-Object -Maximum).Maximum
    
    return @{
        TestName = $TestName
        Times = $times
        Average = $avgTime
        Minimum = $minTime
        Maximum = $maxTime
    }
}

# 开始性能测试
$results = @()

Write-Host "1. Starship 初始化性能测试" -ForegroundColor Yellow
Write-Host "  无缓存模式:" -ForegroundColor White
$noCacheStarship = Measure-Performance -TestName "Starship (无缓存)" -TestScript {
    Test-StarshipInit
}

Write-Host "  缓存模式:" -ForegroundColor White
$cachedStarship = Measure-Performance -TestName "Starship (缓存)" -TestScript {
    Test-StarshipInit -UseCache
}

$results += $noCacheStarship, $cachedStarship
Write-Host ""

Write-Host "2. Zoxide 初始化性能测试" -ForegroundColor Yellow
Write-Host "  无缓存模式:" -ForegroundColor White
$noCacheZoxide = Measure-Performance -TestName "Zoxide (无缓存)" -TestScript {
    Test-ZoxideInit
}

Write-Host "  缓存模式:" -ForegroundColor White
$cachedZoxide = Measure-Performance -TestName "Zoxide (缓存)" -TestScript {
    Test-ZoxideInit -UseCache
}

$results += $noCacheZoxide, $cachedZoxide
Write-Host ""

Write-Host "3. 复杂配置加载性能测试" -ForegroundColor Yellow
Write-Host "  无缓存模式:" -ForegroundColor White
$noCacheComplex = Measure-Performance -TestName "复杂配置 (无缓存)" -TestScript {
    Test-ComplexConfig
}

Write-Host "  缓存模式:" -ForegroundColor White
$cachedComplex = Measure-Performance -TestName "复杂配置 (缓存)" -TestScript {
    Test-ComplexConfig -UseCache
}

$results += $noCacheComplex, $cachedComplex
Write-Host ""

# 显示性能对比结果
Write-Host "=== 性能对比结果 ===" -ForegroundColor Cyan
Write-Host ""

# Starship 对比
$starshipSpeedup = [math]::Round($noCacheStarship.Average / $cachedStarship.Average, 2)
Write-Host "📊 Starship 初始化:" -ForegroundColor White
Write-Host "   无缓存平均: $([math]::Round($noCacheStarship.Average, 2)) ms" -ForegroundColor Gray
Write-Host "   缓存平均:   $([math]::Round($cachedStarship.Average, 2)) ms" -ForegroundColor Gray
Write-Host "   性能提升:   ${starshipSpeedup}x" -ForegroundColor Green
Write-Host ""

# Zoxide 对比
$zoxideSpeedup = [math]::Round($noCacheZoxide.Average / $cachedZoxide.Average, 2)
Write-Host "📊 Zoxide 初始化:" -ForegroundColor White
Write-Host "   无缓存平均: $([math]::Round($noCacheZoxide.Average, 2)) ms" -ForegroundColor Gray
Write-Host "   缓存平均:   $([math]::Round($cachedZoxide.Average, 2)) ms" -ForegroundColor Gray
Write-Host "   性能提升:   ${zoxideSpeedup}x" -ForegroundColor Green
Write-Host ""

# 复杂配置对比
$complexSpeedup = [math]::Round($noCacheComplex.Average / $cachedComplex.Average, 2)
Write-Host "📊 复杂配置加载:" -ForegroundColor White
Write-Host "   无缓存平均: $([math]::Round($noCacheComplex.Average, 2)) ms" -ForegroundColor Gray
Write-Host "   缓存平均:   $([math]::Round($cachedComplex.Average, 2)) ms" -ForegroundColor Gray
Write-Host "   性能提升:   ${complexSpeedup}x" -ForegroundColor Green
Write-Host ""

# 总体性能提升
$totalNoCacheTime = $noCacheStarship.Average + $noCacheZoxide.Average + $noCacheComplex.Average
$totalCacheTime = $cachedStarship.Average + $cachedZoxide.Average + $cachedComplex.Average
$totalSpeedup = [math]::Round($totalNoCacheTime / $totalCacheTime, 2)

Write-Host "🚀 总体性能提升:" -ForegroundColor Cyan
Write-Host "   无缓存总时间: $([math]::Round($totalNoCacheTime, 2)) ms" -ForegroundColor Gray
Write-Host "   缓存总时间:   $([math]::Round($totalCacheTime, 2)) ms" -ForegroundColor Gray
Write-Host "   总体提升:     ${totalSpeedup}x" -ForegroundColor Green
Write-Host ""

# 显示缓存统计
Write-Host "📈 缓存统计信息:" -ForegroundColor Yellow
$cacheStats = Get-CacheStats
Write-Host ""

# 节省时间计算
$timeSaved = $totalNoCacheTime - $totalCacheTime
Write-Host "💡 实际应用效果:" -ForegroundColor White
Write-Host "   每次 PowerShell 启动可节省: $([math]::Round($timeSaved, 2)) ms" -ForegroundColor Green
Write-Host "   按每天启动 10 次计算，每天节省: $([math]::Round($timeSaved * 10 / 1000, 2)) 秒" -ForegroundColor Green
Write-Host "   按每年工作 250 天计算，每年节省: $([math]::Round($timeSaved * 10 * 250 / 1000 / 60, 2)) 分钟" -ForegroundColor Green
Write-Host ""

# 清理测试缓存
Write-Host "清理测试缓存..." -ForegroundColor Yellow
Clear-ExpiredCache -Force | Out-Null

Write-Host "=== 测试完成 ===" -ForegroundColor Cyan
Write-Host "建议在 PowerShell Profile 中使用 Invoke-WithCache 来缓存耗时的初始化操作！" -ForegroundColor Green