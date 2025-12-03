编写高性能的 PowerShell (pwsh) 脚本不仅仅是让代码“能跑”，而是要理解 PowerShell 的对象模型、管道机制以及底层的 .NET 框架。

以下是编写高性能 PowerShell 脚本的核心最佳实践，按重要性排序：

### 1. 避免在数组中使用 `+=` (最常见的性能杀手)

在 PowerShell 中，数组是固定大小的。每次使用 `+=` 向数组添加元素时，PowerShell 实际上会创建一个**新的、更大的数组**，将旧数据复制过去，加上新数据，然后销毁旧数组。随着数据量增加，这会变成 O(n²) 的操作，速度极慢。

**错误做法：**

```powershell
$results = @()
foreach ($item in $list) {
    $results += $item  # 随着 $list 变大，速度指数级下降
}
```

**最佳实践 1：使用 `System.Collections.Generic.List[T]`**

```powershell
$results = [System.Collections.Generic.List[Object]]::new()
foreach ($item in $list) {
    $results.Add($item)
}
```

**最佳实践 2：直接将循环赋值给变量 (最推荐)**
PowerShell 会自动处理管道输出并将其收集为数组（实际上是一个 ArrayList，最后转为 Array），这是最快且代码最简洁的方法。

```powershell
$results = foreach ($item in $list) {
    # 处理逻辑
    $item # 输出对象
}
```

---

### 2. 循环结构的选择：`foreach` vs `ForEach-Object`

PowerShell 的管道 (`|`) 即使在内存中也有序列化/反序列化的开销，并且每个对象都会触发函数调用开销。

* **`ForEach-Object` (管道)**: 最慢，但内存占用低（流式处理）。
* **`foreach ($x in $y)` (语句)**: 很快，但需要将所有数据先加载到内存中。
* **`.ForEach()` (方法)**: 在 PowerShell 4.0+ 中针对集合的方法，速度极快。

**性能对比：**

```powershell
# 慢 (适合节省内存)
1..10000 | ForEach-Object { $_ * 2 }

# 快 (适合追求速度)
foreach ($i in 1..10000) { $i * 2 }

# 极快 (语法稍微受限)
(1..10000).ForEach({ $_ * 2 })
```

**建议：** 除非内存受限（需要流式处理），否则在脚本内部处理大量数据时，优先使用 `foreach` 语句。

---

### 3. "Filter Left" 原则 (左侧过滤)

尽早在管道的左侧（数据源头）过滤数据，而不是把所有数据取回来后再用 `Where-Object` 过滤。

**错误做法：**

```powershell
Get-ChildItem -Path C:\ -Recurse | Where-Object { $_.Extension -eq ".log" }
# 这会获取成千上万个文件对象，然后再一个个检查扩展名。
```

**最佳实践：**

```powershell
Get-ChildItem -Path C:\ -Recurse -Filter "*.log"
# 让文件系统驱动程序只返回你需要的文件。
```

*这同样适用于 Active Directory (`-Filter`), Event Logs, SQL 查询等。*

---

### 4. 字符串操作优化

与数组类似，字符串在 .NET 中是不可变的。在循环中使用 `+=` 拼接字符串是性能灾难。

**错误做法：**

```powershell
$log = ""
foreach ($line in $data) {
    $log += $line + "`n"
}
```

**最佳实践：使用 StringBuilder**

```powershell
$sb = [System.Text.StringBuilder]::new()
foreach ($line in $data) {
    [void]$sb.AppendLine($line)
}
$log = $sb.ToString()
```

---

### 5. 输出与控制台交互

写控制台 (`Write-Host`) 非常慢，因为它需要与主机 UI 交互。

* **避免** `Write-Host` 进行大量输出。
* **避免** 多余的 `Write-Output`。在函数中直接放置对象就会被输出，不需要显式调用 `Write-Output`（这也有轻微开销）。
* **压制输出**：如果你调用了一个有返回值的 .NET 方法但不需要结果，请使用 `[void]` 或 `$null =`，否则 PowerShell 会花时间处理该对象并试图将其写入管道。

```powershell
# 慢
$list.Add("item") 
# (List.Add 返回索引号，PS会把它打印到控制台，这很慢)

# 快
[void]$list.Add("item")
# 或者
$null = $list.Add("item")
```

---

### 6. 对象创建

创建自定义对象是脚本中常见的操作。

**错误做法 (PS 2.0 时代)：**

```powershell
$obj = New-Object PSObject
$obj | Add-Member -MemberType NoteProperty -Name "ID" -Value 1
```

**最佳实践 (PS 3.0+ 类型转换)：**
这比 `New-Object` 快大约 10 倍。

```powershell
$obj = [PSCustomObject]@{
    ID   = 1
    Name = "Test"
}
```

---

### 7. 处理大文件：`Get-Content` 的陷阱

`Get-Content` 默认是一行一行读取并作为单独的字符串对象发送到管道，对于大文件非常慢。

**优化 1：使用 `-ReadCount`**
这会一次发送多行（数组）到管道，显著减少管道开销。

```powershell
Get-Content huge.log -ReadCount 1000 | ForEach-Object {
    # $_ 现在是一个包含1000行的数组
    foreach ($line in $_) { ... }
}
```

**优化 2：使用 .NET 类 (极致性能)**
如果只需要读取，直接使用 .NET 的 StreamReader。

```powershell
[System.IO.File]::ReadAllLines("huge.log")
# 或者流式读取
$reader = [System.IO.File]::OpenText("huge.log")
while ($null -ne ($line = $reader.ReadLine())) { ... }
$reader.Close()
```

---

### 8. 利用并行处理 (PowerShell 7+)

在 PowerShell 5.1 中，实现多线程（Runspaces）非常复杂。但在 PowerShell 7 (pwsh) 中，`ForEach-Object` 增加了 `-Parallel` 参数。

**场景：** 当你的操作受限于 I/O（如 Ping 多个服务器、查询 API、读写文件）而非 CPU 时。

```powershell
# 串行 (耗时 10秒)
1..10 | ForEach-Object { Start-Sleep -Seconds 1 }

# 并行 (耗时 约2秒，默认一次跑5个线程)
1..10 | ForEach-Object -Parallel {
    Start-Sleep -Seconds 1
} -ThrottleLimit 5
```

*注意：对于简单的内存计算（如数学运算），并行化的启动开销反而可能让速度变慢。仅在有 I/O 等待时使用并行。*

---

### 9. 避免使用 `ScriptBlock` 作为过滤器

`Where-Object` 使用脚本块 `{ $_.Property -eq 'Value' }` 会为每个对象创建一个新的作用域。

**优化：使用比较语句 (PS 3.0+)**
如果逻辑简单，不要用花括号。

```powershell
# 较慢
$users | Where-Object { $_.Age -gt 30 }

# 较快 (不再解析 ScriptBlock)
$users | Where-Object Age -gt 30
```

---

### 10. 总结清单

1. **测量它**：使用 `Measure-Command { 你的代码 }` 来验证优化效果。不要凭感觉猜。
2. **Filter Left**：在数据源头过滤。
3. **抛弃 `+=`**：使用 `[System.Collections.Generic.List[object]]` 或直接赋值循环结果。
4. **少用 `Write-Host`**：仅用于给用户展示必要的进度。
5. **必要时下潜到 .NET**：PowerShell 是 .NET 的封装，直接调用 `[System.Math]` 或 `[System.IO]` 通常比对应的 Cmdlet 快。
