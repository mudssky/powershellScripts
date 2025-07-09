<#
.SYNOPSIS
    PSUtils 帮助搜索功能使用示例

.DESCRIPTION
    演示如何使用新的高性能帮助搜索功能来快速查找和了解模块中的函数

.NOTES
    运行此脚本前请确保已导入psutils模块
#>

# 导入psutils模块（如果尚未导入）
if (-not (Get-Module psutils)) {
    Import-Module "$PSScriptRoot\..\psutils.psd1" -Force
}

Write-Host "=== PSUtils 帮助搜索功能演示 ===" -ForegroundColor Cyan
Write-Host ""

# 示例1: 搜索包含特定关键词的函数
Write-Host "示例1: 搜索包含'install'关键词的函数" -ForegroundColor Yellow
Write-Host "命令: Find-PSUtilsFunction 'install'" -ForegroundColor Gray
Write-Host ""
Find-PSUtilsFunction "install"
Write-Host ""
Read-Host "按回车键继续..."
Clear-Host

# 示例2: 搜索操作系统相关的函数
Write-Host "示例2: 搜索操作系统相关的函数" -ForegroundColor Yellow
Write-Host "命令: Find-PSUtilsFunction 'os'" -ForegroundColor Gray
Write-Host ""
Find-PSUtilsFunction "os"
Write-Host ""
Read-Host "按回车键继续..."
Clear-Host

# 示例3: 获取特定函数的详细帮助
Write-Host "示例3: 获取特定函数的详细帮助" -ForegroundColor Yellow
Write-Host "命令: Get-FunctionHelp 'Get-OperatingSystem'" -ForegroundColor Gray
Write-Host ""
Get-FunctionHelp "Get-OperatingSystem"
Write-Host ""
Read-Host "按回车键继续..."
Clear-Host

# 示例4: 显示所有函数的详细信息
Write-Host "示例4: 显示所有函数的详细信息（前5个）" -ForegroundColor Yellow
Write-Host "命令: Find-PSUtilsFunction -ShowDetails | Select-Object -First 5" -ForegroundColor Gray
Write-Host ""
$allFunctions = Find-PSUtilsFunction -ShowDetails
if ($allFunctions.Count -gt 5) {
    $allFunctions | Select-Object -First 5
    Write-Host "... 还有 $($allFunctions.Count - 5) 个函数" -ForegroundColor Gray
} else {
    $allFunctions
}
Write-Host ""
Read-Host "按回车键继续..."
Clear-Host

# 示例5: 在指定路径中搜索
Write-Host "示例5: 在指定路径中搜索函数" -ForegroundColor Yellow
Write-Host "命令: Search-ModuleHelp -SearchTerm 'Get' -ModulePath 'C:\path\to\module'" -ForegroundColor Gray
Write-Host ""
Write-Host "注意: 这个示例需要指定实际存在的模块路径" -ForegroundColor Red
Write-Host "示例命令: Search-ModuleHelp -SearchTerm 'Get' -ModulePath '$PSScriptRoot\..\modules'" -ForegroundColor Gray
Write-Host ""
Search-ModuleHelp -SearchTerm "Get" -ModulePath "$PSScriptRoot\..\modules"
Write-Host ""
Read-Host "按回车键继续..."
Clear-Host

# 示例6: 性能对比演示
Write-Host "示例6: 性能对比演示" -ForegroundColor Yellow
Write-Host "比较传统Get-Help和新的Search-ModuleHelp的性能差异" -ForegroundColor Gray
Write-Host ""

# 测试新方法的性能
Write-Host "测试新的Search-ModuleHelp性能..." -ForegroundColor Green
$newMethodTime = Measure-Command {
    Find-PSUtilsFunction "Get" | Out-Null
}
Write-Host "新方法耗时: $($newMethodTime.TotalMilliseconds) 毫秒" -ForegroundColor Green

# 如果可能，测试传统Get-Help的性能（仅作演示）
Write-Host "传统Get-Help方法会扫描所有已加载的模块，通常耗时更长" -ForegroundColor Yellow
Write-Host "新方法的优势:" -ForegroundColor Cyan
Write-Host "  - 只搜索指定模块，避免全局扫描" -ForegroundColor White
Write-Host "  - 直接解析文件，无需模块加载开销" -ForegroundColor White
Write-Host "  - 支持模糊搜索和精确匹配" -ForegroundColor White
Write-Host "  - 提供更好的输出格式" -ForegroundColor White
Write-Host ""

# 使用技巧
Write-Host "=== 使用技巧 ===" -ForegroundColor Cyan
Write-Host "1. 使用Find-PSUtilsFunction快速搜索当前模块" -ForegroundColor White
Write-Host "2. 使用Get-FunctionHelp获取特定函数的详细信息" -ForegroundColor White
Write-Host "3. 使用Search-ModuleHelp在任意模块路径中搜索" -ForegroundColor White
Write-Host "4. 添加-ShowDetails参数获取完整的帮助信息" -ForegroundColor White
Write-Host "5. 搜索关键词支持模糊匹配，可以搜索函数名或描述内容" -ForegroundColor White
Write-Host ""

Write-Host "演示完成！" -ForegroundColor Green
Write-Host "你现在可以使用这些函数来快速搜索和查看模块帮助信息了。" -ForegroundColor Green
