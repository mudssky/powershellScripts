# 🚀 SSH 反向代理速查表 (Cheatsheet)

**核心原理**：将云服务器的流量 $\rightarrow$ 塞入 SSH 隧道 $\rightarrow$ 传回你本地/局域网 $\rightarrow$ 转发给 Clash $\rightarrow$ 出海。

## ✅ 前置检查

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

### 2. 配置文件方式：专用隧道 Host

*配置一次，以后直接 `ssh alias` 即可建立隧道。建议把隧道放在专用 Host 中，不要和 VS Code Remote SSH 或 zellij 登录 Host 混用。*

编辑文件：`~/.ssh/config` (Mac/Linux) 或 `%USERPROFILE%\.ssh\config` (Windows)

```sshconfig
Host my-cloud-server-tunnel      # 专用隧道别名
    HostName 1.2.3.4             # 服务器公网 IP
    User root                    # 用户名
    Port 22                      # SSH 端口
    ExitOnForwardFailure yes     # 转发端口绑定失败时直接失败，避免半成功连接
    # ↓↓↓ 核心配置 ↓↓↓
    # 格式：RemoteForward <服务器监听端口> <本地视角的目标IP>:<目标端口>

    # 选项1：用本机的代理
    RemoteForward 7890 127.0.0.1:7890

    # 选项2：用软路由的代理 (二选一)
    # RemoteForward 7890 192.168.50.1:7890
```

连接时用：

```bash
ssh -N my-cloud-server-tunnel
```

`-N` 表示不打开远程 Shell，只维护代理隧道。这样 VS Code、普通终端、zellij 登录都可以复用远端 `127.0.0.1:7890`，但不会各自抢占同一个远端监听端口。

---

### 3. VS Code 配置：保持 SSH Host 干净

*目标：VS Code 连接稳定，远程终端按需使用已存在的代理端口。*

#### 第一步：VS Code Host 只放连接稳定性配置

VS Code Remote SSH 通常会建立多条 SSH 连接。如果这些连接都带同一个 `RemoteForward 7890`，后续连接可能绑定失败，甚至让排查断联时难以判断根因。建议 VS Code 使用不带 `RemoteForward`、`RemoteCommand`、`RequestTTY` 的 Host：

```sshconfig
Host my-cloud-server-vscode
    HostName 1.2.3.4
    User root
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ConnectTimeout 30
```

如果正在排查十几分钟后断联的问题，可以先注释掉普通 Host 中的 `RemoteForward`，只保留上面三个 VS Code 侧参数观察一段时间。这样能把“代理端口冲突”和“连接空闲/网络抖动”拆开看。

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

如果远程 `127.0.0.1:7890` 没有监听，说明当前没有独立隧道在运行。此时先启动第 2 节的 `*-tunnel` Host，而不是把 `RemoteForward` 重新放回 VS Code Host。

#### 第三步：常用配置实例

下面这组配置把同一台服务器拆成三个入口：VS Code 只负责非交互开发连接，zellij 只负责人工终端会话，tunnel 只负责代理端口转发。

```sshconfig
# VS Code Remote SSH 入口：保持非交互，不带 RemoteCommand / RequestTTY / RemoteForward。
Host ai-admin-vscode
  HostName 192.168.27.77
  User administrator
  ServerAliveInterval 60
  ServerAliveCountMax 3
  ConnectTimeout 30

# zellij 人工入口：保留 TTY 与远程命令，排查期先不加保活参数。
Host ai-admin-zellij
  HostName 192.168.27.77
  User administrator
  RequestTTY yes
  RemoteCommand bash -lc 'cd ~/projects/env/powershellScripts && exec /home/linuxbrew/.linuxbrew/bin/zellij attach -c powershellScripts'

# 独立代理入口：只在需要远端 127.0.0.1:7890 代理时手动启动。
Host ai-admin-tunnel
  HostName 192.168.27.77
  User administrator
  ExitOnForwardFailure yes
  RemoteForward 7890 127.0.0.1:7890
```

使用方式：

```bash
# VS Code 里选择 ai-admin-vscode

# 终端里进入 zellij 工作区
ssh ai-admin-zellij

# 需要代理时单独开一个窗口维持隧道
ssh -N ai-admin-tunnel
```

如果代理目标不是本机 Clash，而是局域网软路由，把 `RemoteForward` 的目标地址换成软路由 IP：

```sshconfig
RemoteForward 7890 192.168.50.1:7890
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

### 5. 长连接断联排查：VS Code、zellij、RemoteForward 混用

适用于这类现象：Windows 客户端连接 Linux 服务器，SSH 配置里同时有 `RemoteForward`、`RequestTTY`、`RemoteCommand` 自动 attach zellij；连接通常不是秒断，而是十几分钟后断开。VS Code Remote SSH 也会断，但 zellij/RemoteCommand 连接更频繁。

#### 先看历史日志，不要只盯实时日志

十几分钟后才断的场景，先查历史更划算：

```bash
# 近 7 天做模式统计：看是否集中出现 disconnect、timeout、reset、kex、forward 失败
journalctl -u ssh -u sshd --since "7 days ago" --no-pager \
  | grep -Ei "192\.168\.21\.108|disconnect|closed|reset|timeout|broken|session closed|error|fatal|kex|forward|MaxStartups|drop connection"

# 近 24 小时细看：结合 last 的登录/退出时间判断会话持续多久
journalctl -u ssh -u sshd --since "24 hours ago" --no-pager
last -Fai | grep "192.168.21.108" | head -n 80
```

如果知道某次大概断开时间，做前后 2-5 分钟切片：

```bash
# 替换成实际断开时间窗口
journalctl -u ssh -u sshd \
  --since "YYYY-MM-DD HH:MM:SS" \
  --until "YYYY-MM-DD HH:MM:SS" \
  --no-pager

journalctl --since "YYYY-MM-DD HH:MM:SS" --until "YYYY-MM-DD HH:MM:SS" --no-pager \
  | grep -Ei "192\.168\.21\.108|disconnect|closed|reset|timeout|broken|session closed|error|fatal|kex|forward"
```

日志解读：

| 日志特征 | 优先怀疑 |
| :--- | :--- |
| `Received disconnect ... disconnected by user` | 客户端、VS Code Remote SSH、终端窗口或本地网络主动关闭 |
| `timeout` / `broken pipe` / `reset by peer` | 网络抖动、Windows 睡眠/省电、NAT/防火墙空闲超时 |
| `kex_exchange_identification` / `MaxStartups` / 大量短连接 | VS Code 多连接、客户端重连风暴、服务端未认证连接限流 |
| 只有 `pam_unix(sshd:session): session closed` | 需要结合前后 2-5 分钟日志、客户端 `ssh -vvv` 和远程命令退出状态判断 |

#### 核查 sshd 配置与连接数量

连接数量通常不是“已建立会话被踢掉”的唯一原因，但它会放大问题：VS Code 会开多条 SSH 连接，多个连接如果都带同一个 `RemoteForward 7890`，容易出现端口冲突或半成功连接。

```bash
# 看服务端实际生效配置
sshd -T | grep -Ei 'clientalive|tcpkeepalive|allowtcpforwarding|gatewayports|permittty|maxsessions|maxstartups|loglevel'

# 看配置来源
grep -RniE 'ClientAlive|TCPKeepAlive|AllowTcpForwarding|GatewayPorts|PermitTTY|MaxSessions|MaxStartups|LogLevel' \
  /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null

# 看同一用户、同一客户端的 SSH 连接和进程
pgrep -af "sshd: administrator"
ss -tnp state established '( sport = :22 or dport = :22 )' | grep "192.168.21.108"
```

判断要点：

* `MaxStartups` 主要影响未认证的新连接，常见表现是新连接在 kex/认证阶段失败。
* `MaxSessions` 主要影响同一条 SSH 连接内能打开多少 session/channel，VS Code 场景要核查，但它不一定直接解释已有 zellij attach 会话断开。
* 如果日志里有大量短时间 `Accepted publickey`，说明客户端或 VS Code 可能在频繁重连。

#### 核查 RemoteForward 7890 是否冲突

同一个远端监听地址和端口通常只能被一个 SSH 连接占用。多个 Host 或多条 VS Code 连接都声明 `RemoteForward 7890 ...` 时，后来的连接可能绑定失败。

```bash
# 看远端 7890 是否由 sshd 监听，以及属于哪个进程
ss -ltnp | grep -E ":22|:7890"

# 看当前 22/7890 相关连接
ss -tnp | grep -E "192.168.21.108|:7890|:22"

# 验证代理链路
curl -I --proxy http://127.0.0.1:7890 https://www.google.com
```

建议在 SSH 配置中加上：

```sshconfig
ExitOnForwardFailure yes
```

这样 `RemoteForward 7890` 绑定失败时会直接失败，避免进入“SSH 登录成功但代理没有成功”的状态。

#### 核查 zellij attach 是否只是退出了前台连接

zellij session 还在，不代表当前 SSH attach 连接没有退出。`RemoteCommand` 的命令退出后，SSH 会话也会结束。

```bash
zellij list-sessions
ps -ef | grep -E "sshd: administrator|zellij" | grep -v grep
```

推荐把 `RemoteCommand` 写成 `bash -lc` + `exec`，让远程命令生命周期更直观：

```sshconfig
RemoteCommand bash -lc 'cd ~/projects/ai/java/xhgj-ai-platform && exec /home/linuxbrew/.linuxbrew/bin/zellij attach -c proj-xhgj-ai-platform'
```

#### 拆分 VS Code Host 与人工 zellij Host

不要让 VS Code Remote SSH 复用带 `RemoteCommand` 的 Host。VS Code 需要非交互连接，`RemoteCommand`、`RequestTTY`、`RemoteForward` 都可能干扰它的连接管理。排查期间建议只给 VS Code Host 加客户端侧保活与连接超时，zellij Host 先保持原样，避免一次改变太多变量。

```sshconfig
# VS Code Remote SSH 入口：非交互连接，只放保活与连接超时。
Host proj-xhgj-ai-platform-vscode
  HostName 192.168.27.77
  User administrator
  ServerAliveInterval 60
  ServerAliveCountMax 3
  ConnectTimeout 30

# zellij 人工入口：保留 TTY 与 RemoteCommand，排查期先不加保活参数。
Host proj-xhgj-ai-platform-zellij
  HostName 192.168.27.77
  User administrator
  RequestTTY yes
  RemoteCommand bash -lc 'cd ~/projects/ai/java/xhgj-ai-platform && exec /home/linuxbrew/.linuxbrew/bin/zellij attach -c proj-xhgj-ai-platform'

# 独立代理入口：需要代理时用 ssh -N 启动，避免 VS Code 多连接抢端口。
Host proj-xhgj-ai-platform-tunnel
  HostName 192.168.27.77
  User administrator
  ExitOnForwardFailure yes
  RemoteForward 7890 192.168.21.108:7890
```

如果 VS Code 也需要代理，建议只保留一个连接负责 `RemoteForward 7890`。可以先用独立终端维持隧道：

```bash
ssh -N -o ExitOnForwardFailure=yes -R 7890:192.168.21.108:7890 administrator@192.168.27.77
# 或者使用上面的专用 Host
ssh -N proj-xhgj-ai-platform-tunnel
```

然后 VS Code Host 不再声明同一个 `RemoteForward 7890`，避免多连接抢同一端口。

---

### 常见问题排查 (Troubleshooting)

| 问题现象 | 原因分析 | 解决方案 |
| :--- | :--- | :--- |
| **连软路由失败** | 软路由拒绝了非本机的请求 | 软路由 Clash 设置中勾选 **Allow LAN** |
| **VS Code 连接变慢** | SSH 尝试连接代理超时 | 检查本地 IP 是否填错，或本地代理是否开启 |
| **端口被占用** | 服务器上已有程序占用了 7890 | 修改 `RemoteForward` 的第一个端口号 (如 `8888 127.0.0.1:7890`) |
| **Git 依然慢** | Git 有单独的配置 | 运行 `git config --global http.proxy http://127.0.0.1:7890` |
| **后台隧道无法关闭** | 使用了 `-f` 参数，进程在后台运行 | `ps aux | grep "ssh -NfR"`查找进程，`kill <PID>` 关闭 |
| **隧道自动断开** | SSH 连接超时或网络不稳定 | 在专用隧道 Host 中添加 `ServerAliveInterval 60` 保持心跳，或先用前台 `ssh -N` 观察日志 |
| **VS Code / zellij 十几分钟后断开** | 客户端主动断开、网络空闲超时、多连接抢 `RemoteForward`、`RemoteCommand` 退出都可能触发 | 先查近 7 天历史日志；排查期先注释普通 Host 的 `RemoteForward`，只给 VS Code Host 加 `ServerAliveInterval 60`、`ServerAliveCountMax 3`、`ConnectTimeout 30`，zellij Host 暂不加保活参数 |
