# rg 使用指南与日志排查速查表

`rg`（ripgrep）是命令行里最常用的文本搜索工具之一，速度快，默认会自动跳过 `.gitignore` 中的内容，也比传统 `grep` 更适合代码库和日志目录。

本文分两部分：

1. 基础使用指南：帮助你快速上手 `rg`
2. 查日志常用操作：直接复制就能用的命令模板

---

## 1. 基础语法

```powershell
rg [选项] PATTERN [PATH ...]
```

常见例子：

```powershell
rg error
rg "timeout"
rg -n -i "connection refused" logs
rg -F "GET /health" .\logs\app.log
```

说明：

- `PATTERN` 默认按正则表达式处理
- `PATH` 不写时，默认搜索当前目录
- 在 PowerShell 中，优先使用单引号包裹模式，例如 `rg 'error|warn'`
- 如果只是查固定字符串，不需要正则，优先用 `-F`，更快也更稳

---

## 2. 最常用参数

| 参数 | 作用 | 示例 |
| :--- | :--- | :--- |
| `-n` | 显示行号 | `rg -n error` |
| `-i` | 忽略大小写 | `rg -i timeout` |
| `-F` | 按固定字符串搜索，不当正则解释 | `rg -F '[ERROR]' logs` |
| `-w` | 按完整单词匹配 | `rg -w error` |
| `-v` | 反向匹配，排除命中行 | `rg -v healthcheck app.log` |
| `-c` | 只显示每个文件的命中次数 | `rg -c error logs` |
| `-l` | 只显示命中的文件名 | `rg -l timeout src` |
| `--files` | 列出可搜索文件，不做正文匹配 | `rg --files` |
| `-g` | 用 glob 限定文件范围 | `rg error -g '*.log'` |
| `-t` | 按文件类型筛选 | `rg TODO -t ps1` |
| `-A 3` | 显示命中后 3 行 | `rg -A 3 error app.log` |
| `-B 3` | 显示命中前 3 行 | `rg -B 3 error app.log` |
| `-C 3` | 显示命中前后各 3 行 | `rg -C 3 error app.log` |
| `--hidden` | 包含隐藏文件 | `rg --hidden token .` |
| `-uuu` | 不忽略隐藏文件、二进制文件、ignore 规则 | `rg -uuu secret .` |
| `--sort path` | 按路径排序输出 | `rg error logs --sort path` |
| `--max-count 20` | 最多显示 20 条命中 | `rg --max-count 20 error logs` |
| `-o` | 仅输出匹配到的片段 | `rg -o '\d{3}' app.log` |
| `--stats` | 输出搜索统计信息 | `rg error logs --stats` |

---

## 3. 基础场景

### 查某个关键词

```powershell
rg -n 'timeout'
```

### 忽略大小写

```powershell
rg -n -i 'error'
```

### 查固定文本而不是正则

如果内容里有 `[`、`]`、`(`、`)`、`.`、`*` 这类字符，优先使用 `-F`：

```powershell
rg -n -F '[ERROR]' .\logs
```

### 只在某类文件里搜

```powershell
rg -n 'Invoke-' -g '*.ps1'
rg -n 'Exception' -g '*.log' .\logs
rg -n 'TODO' -t md
```

### 排除目录或文件

```powershell
rg -n 'error' .\logs -g '!archive/**'
rg -n 'error' .\logs -g '!*.bak'
```

### 显示上下文

排查问题时，上下文通常比“只看到一行命中”更重要：

```powershell
rg -n -C 2 'NullReferenceException' .\logs\app.log
rg -n -A 5 'panic' .\logs\service.log
rg -n -B 3 'Started request' .\logs\api.log
```

### 只看命中的文件

```powershell
rg -l 'Connection refused' .\logs
```

### 统计命中次数

```powershell
rg -c 'error' .\logs
```

---

## 4. 正则表达式常用写法

### 或条件

```powershell
rg -n 'error|warn|fatal' .\logs
```

### 数字、HTTP 状态码、请求 ID

```powershell
rg -n '\b5\d{2}\b' .\logs
rg -n 'requestId[=: ]+[a-zA-Z0-9-]+' .\logs
```

### 匹配完整单词

避免把 `terror` 里的 `error` 也匹配出来：

```powershell
rg -n -w 'error' .\logs
```

### 多条件同时满足

`rg` 默认不直接写“AND”，通常用 PCRE2：

```powershell
rg -n -P '(?=.*error)(?=.*orderId=12345)' .\logs\app.log
```

说明：

- `-P` 启用 PCRE2，适合高级正则
- 复杂正则性能可能明显下降，只在确实需要时使用

---

## 5. PowerShell 下的实用写法

### 搜当前目录所有可搜索文件

```powershell
rg --files
```

### 搜最近修改的日志文件

先筛出最近修改的文件，再交给 `rg`：

```powershell
Get-ChildItem .\logs -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 10 |
  ForEach-Object { rg -n 'error|warn' $_.FullName }
```

### 只搜 `.log` 和 `.txt`

```powershell
rg -n 'timeout' .\logs -g '*.log' -g '*.txt'
```

### 输出结果再继续处理

```powershell
$matches = rg -n 'error' .\logs
$matches | Select-Object -First 20
```

---

## 6. 查日志常用操作 Cheatsheet

下面这些命令适合直接复制后改关键词。

### 查错误、告警、异常

```powershell
rg -n -i 'error|warn|fatal|exception|panic' .\logs -g '*.log'
```

### 查某个接口或路径

```powershell
rg -n -F 'GET /api/orders' .\logs -g '*.log'
rg -n -F '/health' .\logs -g '*.log'
```

### 查某个用户、订单号、请求 ID

```powershell
rg -n 'userId=12345' .\logs
rg -n 'orderId=20260319001' .\logs
rg -n 'requestId=9f1c2d3e' .\logs
```

### 查 5xx / 4xx

```powershell
rg -n '\b5\d{2}\b' .\logs -g '*.log'
rg -n '\b4\d{2}\b' .\logs -g '*.log'
```

### 查超时、重试、连接失败

```powershell
rg -n -i 'timeout|timed out|retry|connection refused|broken pipe' .\logs
```

### 查启动失败、配置加载失败

```powershell
rg -n -i 'failed to start|startup failed|config.*failed|load.*config' .\logs
```

### 查某段时间附近的上下文

如果你已经知道某个时间点字符串，可以先定位，再带上下文查看：

```powershell
rg -n -C 5 '2026-03-19 10:15' .\logs\app.log
rg -n -C 8 '10:15:3' .\logs\app.log
```

### 排除噪音日志

例如排除健康检查、探针、静态资源请求：

```powershell
rg -n -i 'error|warn' .\logs -g '*.log' | rg -v 'health|/metrics|/favicon.ico'
```

### 找出“哪些文件”出现过异常

```powershell
rg -l -i 'error|fatal|exception' .\logs -g '*.log'
```

### 统计每个日志文件里错误数量

```powershell
rg -c -i 'error|fatal|exception' .\logs -g '*.log'
```

### 只看前几条命中，快速判断方向

```powershell
rg -n -i 'exception|panic' .\logs --max-count 20
```

### 搜压缩日志

如果日志是 `.gz`、`.zip`、`.bz2` 等压缩格式，可尝试：

```powershell
rg -n -z 'error|exception' .\logs
```

说明：

- `-z` 会尝试搜索常见压缩文件内容
- 大文件和压缩包较多时，速度会明显下降

---

## 7. 高频组合模板

### 模板 1：在日志目录中查错误并带上下文

```powershell
rg -n -i -C 3 'error|fatal|exception' .\logs -g '*.log'
```

### 模板 2：查固定请求路径

```powershell
rg -n -F '/api/orders/submit' .\logs -g '*.log'
```

### 模板 3：查某个 ID，并看前后 10 行

```powershell
rg -n -C 10 'requestId=abc-123' .\logs
```

### 模板 4：查错误但过滤健康检查噪音

```powershell
rg -n -i 'error|warn|fatal' .\logs -g '*.log' | rg -v 'health|metrics|readiness|liveness'
```

### 模板 5：只看最近几个文件里的异常

```powershell
Get-ChildItem .\logs -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 |
  ForEach-Object { rg -n -i 'error|exception|panic' $_.FullName }
```

---

## 8. 常见坑

### 正则特殊字符误伤

这类命令容易搜不准：

```powershell
rg '[ERROR]' .\logs
```

因为 `[]` 会被当成正则字符集合。更稳的写法：

```powershell
rg -F '[ERROR]' .\logs
```

### PowerShell 引号问题

优先写成：

```powershell
rg -n 'error|warn' .\logs
```

尽量少用双引号，除非你明确需要 PowerShell 变量插值。

### 没搜到隐藏目录或被 ignore 规则忽略

```powershell
rg -n 'secret' . --hidden
rg -n 'secret' . -uuu
```

### 二进制文件默认被跳过

如果怀疑目标内容在二进制或特殊文件里，可以尝试：

```powershell
rg -n -uuu 'keyword' .
```

---

## 9. 一句话建议

- 查固定文本，用 `-F`
- 排查日志，用 `-n -i -C 3`
- 先缩小文件范围，再搜正文，例如 `-g '*.log'`
- 先看前 20 条，再决定是否扩大范围
- 复杂 AND 条件最后再上 `-P`
