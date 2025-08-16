<#
.SYNOPSIS
    PowerShell 缓存模块 CacheType 功能演示脚本 v1.3.0
    
.DESCRIPTION
    演示 Invoke-WithCache 函数的 CacheType 参数功能，包括：
    - XML 缓存格式（默认）- 适合复杂对象
    - Text 缓存格式 - 适合字符串内容
    - 不同缓存类型的性能对比
    - 缓存文件格式对比
    
.AUTHOR
    mudssky
    
.VERSION
    1.3.0
    
.DATE
    2025-01-07
#>

# 导入缓存模块
Import-Module "$PSScriptRoot\modules\cache.psm1" -Force

Write-Host "=== PowerShell 缓存模块 CacheType 功能演示 v1.3.0 ===" -ForegroundColor Green
Write-Host ""

# 清理之前的演示缓存
$cacheDir = Join-Path $env:LOCALAPPDATA "PowerShellCache"
if (Test-Path $cacheDir) {
    Get-ChildItem $cacheDir -Filter "demo-*.cache.*" | Remove-Item -Force
    Write-Host "已清理之前的演示缓存文件" -ForegroundColor Yellow
}

Write-Host "1. XML 缓存格式演示（默认）" -ForegroundColor Cyan
Write-Host "   适用于：复杂PowerShell对象，保持完整数据类型"

# XML 缓存 - 复杂对象
$complexData = @{
    Name    = "演示数据"
    Numbers = @(1, 2, 3, 4, 5)
    Date    = Get-Date
    Nested  = @{
        Property = "嵌套属性"
        Values   = @("A", "B", "C")
    }
}

$xmlResult = Invoke-WithCache -Key "demo-xml-complex" -CacheType XML -ScriptBlock {
    Write-Host "    执行复杂对象脚本块..." -ForegroundColor Gray
    Start-Sleep -Milliseconds 100
    return $complexData
} -Verbose

Write-Host "    XML缓存结果类型: $($xmlResult.GetType().Name)"
Write-Host "    Name: $($xmlResult.Name)"
Write-Host "    Numbers: $($xmlResult.Numbers -join ', ')"
Write-Host "    Date: $($xmlResult.Date.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "    Nested.Property: $($xmlResult.Nested.Property)"
Write-Host ""

Write-Host "2. Text 缓存格式演示" -ForegroundColor Cyan
Write-Host "   适用于：字符串内容，纯文本存储，性能更好"

# Text 缓存 - 字符串内容
$textContent = @"
这是一个多行文本内容的演示
包含了多行数据
适合使用 Text 缓存格式
时间戳: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

$textResult = Invoke-WithCache -Key "demo-text-content" -CacheType Text -ScriptBlock {
    Write-Host "    执行文本内容脚本块..." -ForegroundColor Gray
    Start-Sleep -Milliseconds 100
    return $textContent
} -Verbose

Write-Host "    Text缓存结果类型: $($textResult.GetType().Name)"
Write-Host "    内容长度: $($textResult.Length) 字符"
Write-Host "    前50个字符: $($textResult.Substring(0, [Math]::Min(50, $textContent.Length)))..."
Write-Host ""

Write-Host "3. Text 缓存自动转换演示" -ForegroundColor Cyan
Write-Host "   Text 缓存会自动将非字符串对象转换为字符串"

# Text 缓存 - 数组自动转换
$arrayData = @("项目1", "项目2", "项目3", "项目4")

$arrayAsTextResult = Invoke-WithCache -Key "demo-text-array" -CacheType Text -ScriptBlock {
    Write-Host "    执行数组转换脚本块..." -ForegroundColor Gray
    Start-Sleep -Milliseconds 100
    return $arrayData
} -Verbose

Write-Host "    原始数组类型: $($arrayData.GetType().Name)"
Write-Host "    Text缓存结果类型: $($arrayAsTextResult.GetType().Name)"
Write-Host "    转换后内容: $arrayAsTextResult"
Write-Host ""

Write-Host "4. 相同Key不同CacheType演示" -ForegroundColor Cyan
Write-Host "   相同的Key使用不同的CacheType会创建不同的缓存文件"

$sameKeyData = "相同Key的测试数据"

# 使用XML格式
$sameKeyXml = Invoke-WithCache -Key "demo-same-key" -CacheType XML -ScriptBlock {
    Write-Host "    执行XML格式脚本块..." -ForegroundColor Gray
    return $sameKeyData
} -Verbose

# 使用Text格式
$sameKeyText = Invoke-WithCache -Key "demo-same-key" -CacheType Text -ScriptBlock {
    Write-Host "    执行Text格式脚本块..." -ForegroundColor Gray
    return $sameKeyData
} -Verbose

Write-Host "    XML结果: $sameKeyXml (类型: $($sameKeyXml.GetType().Name))"
Write-Host "    Text结果: $sameKeyText (类型: $($sameKeyText.GetType().Name))"
Write-Host ""

Write-Host "5. 缓存文件分析" -ForegroundColor Cyan

# 显示创建的缓存文件
$demoFiles = Get-ChildItem $cacheDir -Filter "demo-*.cache.*" | Sort-Object Name
Write-Host "    创建的演示缓存文件:"
foreach ($file in $demoFiles) {
    $size = [Math]::Round($file.Length / 1KB, 2)
    $extension = $file.Extension
    $type = if ($extension -eq '.xml') { 'XML格式' } else { 'Text格式' }
    Write-Host "    - $($file.Name) ($type, ${size}KB)"
}
Write-Host ""

Write-Host "6. 性能对比演示" -ForegroundColor Cyan

# 性能测试数据
$perfTestData = 1..1000 | ForEach-Object { "测试数据行 $_" }

# XML 缓存性能测试
$xmlTime = Measure-Command {
    $xmlPerfResult = Invoke-WithCache -Key "demo-perf-xml" -CacheType XML -ScriptBlock {
        return $perfTestData
    }
}

# Text 缓存性能测试
$textTime = Measure-Command {
    $textPerfResult = Invoke-WithCache -Key "demo-perf-text" -CacheType Text -ScriptBlock {
        return $perfTestData
    }
}

Write-Host "    XML缓存写入时间: $($xmlTime.TotalMilliseconds.ToString('F2'))ms"
Write-Host "    Text缓存写入时间: $($textTime.TotalMilliseconds.ToString('F2'))ms"

# 读取性能测试
$xmlReadTime = Measure-Command {
    $xmlReadResult = Invoke-WithCache -Key "demo-perf-xml" -CacheType XML -ScriptBlock { "不会执行" }
}

$textReadTime = Measure-Command {
    $textReadResult = Invoke-WithCache -Key "demo-perf-text" -CacheType Text -ScriptBlock { "不会执行" }
}

Write-Host "    XML缓存读取时间: $($xmlReadTime.TotalMilliseconds.ToString('F2'))ms"
Write-Host "    Text缓存读取时间: $($textReadTime.TotalMilliseconds.ToString('F2'))ms"
Write-Host ""

Write-Host "7. 最终缓存文件统计" -ForegroundColor Cyan

$allDemoFiles = Get-ChildItem $cacheDir -Filter "demo-*.cache.*" | Sort-Object Extension, Name
$xmlFiles = $allDemoFiles | Where-Object { $_.Extension -eq '.xml' }
$txtFiles = $allDemoFiles | Where-Object { $_.Extension -eq '.txt' }

Write-Host "    XML缓存文件: $($xmlFiles.Count) 个"
foreach ($file in $xmlFiles) {
    $size = [Math]::Round($file.Length / 1KB, 2)
    Write-Host "      - $($file.Name) (${size}KB)"
}

Write-Host "    Text缓存文件: $($txtFiles.Count) 个"
foreach ($file in $txtFiles) {
    $size = [Math]::Round($file.Length / 1KB, 2)
    Write-Host "      - $($file.Name) (${size}KB)"
}

Write-Host ""
Write-Host "=== CacheType 功能演示完成 ===" -ForegroundColor Green
Write-Host ""
Write-Host "主要特性总结:" -ForegroundColor Yellow
Write-Host "✓ XML缓存: 保持完整数据类型，适合复杂PowerShell对象" -ForegroundColor White
Write-Host "✓ Text缓存: 纯文本存储，性能更好，适合字符串内容" -ForegroundColor White
Write-Host "✓ 自动转换: Text缓存自动将非字符串对象转换为字符串" -ForegroundColor White
Write-Host "✓ 独立缓存: 相同Key不同CacheType创建不同缓存文件" -ForegroundColor White
Write-Host "✓ MD5哈希: 使用32位MD5哈希生成缓存文件名" -ForegroundColor White
Write-Host "✓ 向后兼容: 默认使用XML格式，保持与旧版本兼容" -ForegroundColor White