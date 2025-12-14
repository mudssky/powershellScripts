这是一个关于使用 PowerShell (pwsh) 进行网络故障排查的速查表（Cheatsheet）。

需要特别注意的是：**PowerShell Core (pwsh 6/7+) 是跨平台的，但很多强大的网络模组（如 `NetTCPIP`，包含 `Test-NetConnection` 等）主要依赖 Windows 的 WMI/CIM 接口，因此在 Linux 上原生不可用。**

本指南将明确区分 **跨平台通用指令** 和 **Windows 专用指令**，并为 Linux 提供替代方案。

---

### 1. 基础连通性 (ICMP / Ping)

**场景：** 检查服务器是否在线，丢包率。

| 目标 | 命令 (Cross-Platform) | 说明 |
| :--- | :--- | :--- |
| **Ping** | `Test-Connection -TargetName google.com` | 基础 Ping，返回对象。 |
| **Ping (简易)** | `ping google.com` | 调用系统原生二进制文件（推荐在 Linux 上直接用这个）。 |
| **持续 Ping** | `Test-Connection google.com -Count 999` | 指定次数（类似 `-t`）。 |
| **指定源 IP** | `Test-Connection ... -Source 192.168.1.5` | **仅 Windows** 支持 `-Source`。 |

---

### 2. 端口连通性 (TCP / Telnet)

**场景：** 检查防火墙是否放行，服务是否在监听。

#### Windows (使用 `NetTCPIP` 模块)

这是 PowerShell 最强大的网络排查命令。

```powershell
# 检查 80 端口 (类似 telnet/nc)
Test-NetConnection -ComputerName google.com -Port 80

# 简写别名
tnc google.com -p 80

# 路由追踪 (Traceroute)
Test-NetConnection google.com -TraceRoute
```

#### Linux / 跨平台通用方案

Linux 版 pwsh 没有 `Test-NetConnection`。
**方案 A: 使用 .NET 类 (推荐脚本中使用)**

```powershell
# 单行检查 TCP 端口 (返回 True/False)
(New-Object System.Net.Sockets.TcpClient).Connect("192.168.1.1", 22) -eq $null
# 如果没有报错且无输出，通常代表连接成功；报错则失败。
```

**方案 B: 定义一个简单的函数 (模拟 TNC)**
将此代码放入 `profile.ps1`：

```powershell
function Test-Port ($server, $port) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($server, $port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(2000, $false) # 2秒超时
        if(!$wait) { $tcp.Close(); return $false }
        $tcp.EndConnect($connect)
        $tcp.Close()
        return $true
    } catch { return $false }
}
# 使用: Test-Port 192.168.1.1 22
```

---

### 3. DNS 解析

**场景：** 检查域名解析是否正确，使用的是哪个 DNS 服务器。

#### Windows

```powershell
# 详细解析信息
Resolve-DnsName google.com

# 指定 DNS 服务器查询 (类似 @8.8.8.8)
Resolve-DnsName google.com -Server 8.8.8.8

# 查询特定记录类型
Resolve-DnsName -Name google.com -Type TXT
```

#### Linux / 跨平台

Linux 下通常缺少 `Resolve-DnsName`。
**方案 A: 调用原生工具**

```powershell
nslookup google.com
dig google.com
```

**方案 B: 使用 .NET 类**

```powershell
[System.Net.Dns]::GetHostEntry("google.com")
# 或者获取 IP 列表
[System.Net.Dns]::GetHostAddresses("google.com")
```

---

### 4. HTTP/Web 请求 (类似 curl/wget)

**场景：** 检查 API 响应、SSL 证书、HTTP 状态码。**这是完全跨平台的。**

| 目标 | 命令 | 说明 |
| :--- | :--- | :--- |
| **GET 请求** | `Invoke-WebRequest -Uri "https://site.com"` | 别名 `iwr`。返回完整的 HTML/Header 对象。 |
| **仅看状态码** | `(iwr "https://site.com").StatusCode` | 快速检查 200/404/500。 |
| **REST API** | `Invoke-RestMethod -Uri "https://api..."` | 别名 `irm`。自动解析 JSON 为对象。 |
| **忽略 SSL 错误** | `iwr ... -SkipCertificateCheck` | **PS 6/7+** 专用参数。 |
| **查看 Headers** | `(iwr "https://site.com").Headers` | 检查缓存、Server 类型等。 |

**实用技巧：下载文件**

```powershell
Invoke-WebRequest "https://example.com/file.zip" -OutFile "local.zip"
```

---

### 5. 网络接口与配置 (IP/MAC)

**场景：** 查看本机 IP、MAC 地址、网关。

#### Windows

```powershell
# 查看所有网卡详细信息
Get-NetAdapter

# 查看 IP 地址
Get-NetIPAddress -AddressFamily IPv4

# 查看路由表
Get-NetRoute
```

#### Linux / 跨平台

Windows 的 `NetAdapter` 模块在 Linux 不可用。
**方案 A: 原生工具 (推荐)**

```powershell
ip a
ip route
```

**方案 B: .NET 类 (脚本用)**

```powershell
# 获取所有网络接口信息
[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
```

---

### 6. 查看端口占用 (Netstat)

**场景：** 检查本机哪些端口被占用了。

#### Windows

```powershell
# 查看所有 TCP 连接
Get-NetTCPConnection

# 查看特定端口 (如 443)
Get-NetTCPConnection -LocalPort 443

# 查看关联的进程 ID
Get-NetTCPConnection | Select-Object LocalPort, OwningProcess, State
```

#### Linux

PowerShell 在 Linux 无法直接读取内核网络表。
**推荐方案：**

```powershell
# 调用系统工具
ss -tuln
netstat -anp
```

---

### 总结对照表

| 功能 | Windows (Native Cmdlet) | Linux (建议) | 跨平台 .NET (脚本用) |
| :--- | :--- | :--- | :--- |
| **Ping** | `Test-Connection` | `ping` | `Test-Connection` (PS7) |
| **Port Scan** | `Test-NetConnection -Port ...` | `nc -zv` / `Test-Port` (自定义) | `System.Net.Sockets.TcpClient` |
| **DNS** | `Resolve-DnsName` | `dig` / `nslookup` | `[System.Net.Dns]::GetHostEntry` |
| **HTTP** | `Invoke-WebRequest` (iwr) | `Invoke-WebRequest` (iwr) | 同左 |
| **JSON API** | `Invoke-RestMethod` (irm) | `Invoke-RestMethod` (irm) | 同左 |
| **IP Info** | `Get-NetIPAddress` | `ip a` | `NetworkInterface.GetAllNetworkInterfaces()` |
| **Socket Stats**| `Get-NetTCPConnection` | `ss` / `netstat` | 较复杂，不建议 |

### 极简排查流程 (One-Liner 组合)

在任意系统中排查一个 Web 服务故障：

```powershell
# 1. 解析 DNS
[System.Net.Dns]::GetHostAddresses("example.com")

# 2. 测试 TCP 端口 (80/443) - 通用简易版
try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect("example.com", 443); "Open" } catch { "Closed" }

# 3. 测试 HTTP 响应
irm https://example.com -Method Head -ErrorAction SilentlyContinue
```
