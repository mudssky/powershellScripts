# 测试 lint-staged 的文件
function Test-Function {
    $result = Get-Process | Where-Object { $_.Name -eq 'powershell' }
    return $result
}

# 调用函数
$processes = Test-Function
Write-Host "找到 $($processes.Count) 个进程"