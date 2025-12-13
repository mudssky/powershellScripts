# 🚀 SSH 反向代理速查表 (Cheatsheet)

**核心原理**：将云服务器的流量 $\rightarrow$ 塞入 SSH 隧道 $\rightarrow$ 传回你本地/局域网 $\rightarrow$ 转发给 Clash $\rightarrow$ 出海。

### ✅ 前置检查

1. **确定代理地址**：
    * 本机 Clash：通常是 `127.0.0.1`，端口 `7890`。
    * 局域网软路由：通常是 `192.168.x.x` (如 `192.168.50.1`)，端口 `7890`。
2. **软路由/局域网设置**：
    * 如果是连软路由 IP，**必须**在 Clash 设置中开启 **“允许局域网连接 (Allow LAN)”**。

---

### 1. 命令行方式 (临时/一次性)

*适合偶尔登录服务器维护，不想修改配置文件。*

**语法**：
`ssh -R <服务器端口>:<本地视角的目标IP>:<目标端口> <用户>@<服务器IP>`

#### 场景 A：使用本机 Clash

```bash
ssh -R 7890:127.0.0.1:7890 root@1.2.3.4
```

#### 场景 B：使用局域网软路由 (如 192.168.50.1)

```bash
ssh -R 7890:192.168.50.1:7890 root@1.2.3.4
```

#### 场景 C：后台静默运行隧道

```bash
# 使用本机 Clash 的后台隧道
ssh -NfR 7890:127.0.0.1:7890 root@1.2.3.4

# 使用软路由的后台隧道
ssh -NfR 7890:192.168.50.1:7890 root@1.2.3.4
```

**参数详解**：

* **`-N` (No remote command)**：不执行远程命令，也不打开远程 Shell。仅仅维持端口转发管道的存在。
* **`-f` (Background)**：认证成功后转入后台运行，立即归还终端控制权。

**进程管理**：

```bash
# 查看后台 SSH 隧道进程
ps aux | grep "ssh -NfR"

# 关闭指定隧道（替换 PID）
kill 12345

# 关闭所有 SSH 进程（慎用）
killall ssh
```

---

### 2. 配置文件方式 (推荐/永久生效)

*配置一次，以后直接 `ssh alias` 即可自动建立隧道。*

编辑文件：`~/.ssh/config` (Mac/Linux) 或 `%USERPROFILE%\.ssh\config` (Windows)

```ssh
Host my-cloud-server             # 别名
    HostName 1.2.3.4             # 服务器公网 IP
    User root                    # 用户名
    Port 22                      # SSH 端口
    # ↓↓↓ 核心配置 ↓↓↓
    # 格式：RemoteForward <服务器监听端口> <本地视角的目标IP>:<目标端口>
    
    # 选项1：用本机的代理
    RemoteForward 7890 127.0.0.1:7890
    
    # 选项2：用软路由的代理 (二选一)
    # RemoteForward 7890 192.168.50.1:7890
```

---

### 3. VS Code 自动化配置 (终极方案)

*实现：连接即代理，终端自动生效环境变量。*

#### 第一步：配置隧道 (同上)

确保你的 SSH Config 文件中已经添加了 `RemoteForward` (参考第 2 点)。
*VS Code 会自动读取这个 SSH 配置建立连接。*

#### 第二步：配置终端自动注入变量

在 VS Code 中，打开 **设置 (Settings)** $\rightarrow$ **JSON 模式**。
你可以修改 **“用户设置 (User Settings)”** 或 **“远程设置 (Remote Settings)”**。

```json
// settings.json
{
    // 仅针对 Linux 远程终端生效
    "terminal.integrated.env.linux": {
        // 这里的 IP 永远填 127.0.0.1
        // 因为 SSH 把流量映射到了服务器自己的 localhost:7890
        "http_proxy": "http://127.0.0.1:7890",
        "https_proxy": "http://127.0.0.1:7890",
        "all_proxy": "socks5://127.0.0.1:7890" // 如果你也转发了 socks 端口
    }
}
```

---

### 4. 服务器端验证与手动激活

如果不使用 VS Code，或者想确认是否成功。

#### 检查隧道是否打通

登录服务器后输入：

```bash
netstat -tunlp | grep 7890
# 成功标志：看到 127.0.0.1:7890 ... LISTEN ... sshd
```

#### 验证网络

```bash
# 临时测试代理是否有效
curl -I --proxy http://127.0.0.1:7890 https://www.google.com
# 成功标志：HTTP/1.1 200 OK
```

#### Shell 智能脚本 (可选，骚操作)

将以下代码加入服务器的 `~/.bashrc`，登录普通 SSH 终端也能自动检测并开启代理：

```bash
# ~/.bashrc 底部添加
# 自动检测 7890 端口，如果通畅则自动设置代理
(echo > /dev/tcp/127.0.0.1/7890) >/dev/null 2>&1
if [ $? -eq 0 ]; then
    export http_proxy=http://127.0.0.1:7890
    export https_proxy=http://127.0.0.1:7890
    echo "🟢 Proxy Auto-Enabled (via SSH Tunnel)"
fi
```

---

### 常见问题排查 (Troubleshooting)

| 问题现象 | 原因分析 | 解决方案 |
| :--- | :--- | :--- |
| **连软路由失败** | 软路由拒绝了非本机的请求 | 软路由 Clash 设置中勾选 **Allow LAN** |
| **VS Code 连接变慢** | SSH 尝试连接代理超时 | 检查本地 IP 是否填错，或本地代理是否开启 |
| **端口被占用** | 服务器上已有程序占用了 7890 | 修改 `RemoteForward` 的第一个端口号 (如 `8888 127.0.0.1:7890`) |
| **Git 依然慢** | Git 有单独的配置 | 运行 `git config --global http.proxy http://127.0.0.1:7890` |
| **后台隧道无法关闭** | 使用了 `-f` 参数，进程在后台运行 | `ps aux | grep "ssh -NfR"`查找进程，`kill <PID>` 关闭 |
| **隧道自动断开** | SSH 连接超时或网络不稳定 | 在 SSH 配置中添加 `ServerAliveInterval 60` 保持心跳 |
