# OpenSSH RemoteCommand / RemoteForward 排查记录

## 资料来源

* Context7: `/openssh/openssh-portable`
* 仓库文档: `docs/cheatsheet/vscode/remote/ssh-proxy.md`
* 仓库文档: `docs/cheatsheet/terminal/Zellij.md`

## 关键结论

* OpenSSH 客户端支持在 `~/.ssh/config` 中配置 `ServerAliveInterval` 和 `ServerAliveCountMax`，适合验证客户端侧心跳是否能缓解空闲连接或中间网络设备导致的断开。
* OpenSSH 服务端支持 `ClientAliveInterval` 和 `ClientAliveCountMax`，需要通过 `sshd -T` 或读取 `/etc/ssh/sshd_config` / drop-in 配置确认实际值。
* OpenSSH sshd 配置中存在 `MaxSessions` 和 `MaxStartups`。`MaxStartups` 主要影响未认证连接的并发/限流，常见表现是新连接在认证或 kex 阶段失败；`MaxSessions` 主要影响单条 SSH 连接内可打开的 session/channel 数。它们不一定会解释“已建立会话被踢”，但在 VS Code Remote SSH 多连接场景下必须核查。
* 反向转发对应命令行为 `ssh -R remotePort:targetHost:targetPort user@host`，SSH config 中对应 `RemoteForward remotePort targetHost:targetPort`。
* `ExitOnForwardFailure yes` 对本问题很重要：如果远端 `7890` 绑定失败，连接应直接失败，而不是进入一个没有代理隧道的“半成功”状态。
* 多个 SSH 连接同时声明同一个远端监听端口，例如 `RemoteForward 7890 ...`，会引入绑定冲突风险。尤其 VS Code Remote SSH 如果复用同一 Host 配置并开多条连接，可能让代理隧道状态变得不直观。
* `RequestTTY yes` 或 `ssh -t` 适合运行 zellij 这类交互式远程命令。
* `RemoteCommand` 的进程生命周期与 SSH 会话强相关；当远程命令退出时，SSH 会话通常也随之结束。因此 `zellij attach` 被 detach、退出、报错、TTY 关闭时，都可能表现为 SSH 会话结束。
* 仓库现有代理文档已经给出服务端验证方式：检查远端 `127.0.0.1:7890` 是否由 `sshd` 监听，并用 `curl --proxy http://127.0.0.1:7890 ...` 验证代理链路。

## 建议诊断命令

服务端配置：

```bash
sshd -T | grep -Ei 'clientalive|tcpkeepalive|allowtcpforwarding|gatewayports|permittty|maxsessions|maxstartups|loglevel'
grep -RniE 'ClientAlive|TCPKeepAlive|AllowTcpForwarding|GatewayPorts|PermitTTY|MaxSessions|MaxStartups|LogLevel' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null
```

服务端日志：

```bash
journalctl -u ssh -u sshd --since "24 hours ago" --no-pager
journalctl -u ssh -u sshd --since "7 days ago" --no-pager | grep -Ei "192\.168\.21\.108|disconnect|closed|reset|timeout|broken|session closed|error|fatal|kex|forward|MaxStartups|drop connection"
journalctl --since "24 hours ago" --no-pager | grep -Ei "disconnect|closed|reset|timeout|broken|session closed|error|fatal|kex|forward"
last -Fai | head -n 80
```

如果已知某次断开的大概时间，优先做时间切片：

```bash
journalctl -u ssh -u sshd --since "2026-05-11 14:20:00" --until "2026-05-11 14:30:00" --no-pager
journalctl --since "2026-05-11 14:20:00" --until "2026-05-11 14:30:00" --no-pager | grep -Ei "192\.168\.21\.108|disconnect|closed|reset|timeout|broken|session closed|error|fatal|kex|forward"
```

端口与进程：

```bash
ss -ltnp | grep -E ":22|:7890"
ss -tnp | grep -E "192.168.21.108|:7890|:22"
ps -ef | grep -E "sshd: administrator|zellij" | grep -v grep
zellij list-sessions
```

连接数量：

```bash
pgrep -af "sshd: administrator"
ss -tnp state established '( sport = :22 or dport = :22 )' | grep "192.168.21.108"
ss -tnp '( sport = :22 or dport = :22 )' | awk '{print $1}' | sort | uniq -c
journalctl -u ssh -u sshd --since "24 hours ago" --no-pager | grep -Ei "MaxStartups|beginning MaxStartups|drop connection|no more sessions|administratively prohibited|open failed|remote forward|forward"
```

网络对照：

```bash
ping -c 100 192.168.21.108
mtr -rwzc 100 192.168.21.108
```

客户端对照：

```powershell
ssh -vvv proj-xhgj-ai-platform
```

## 推荐临时 SSH 配置

```sshconfig
Host proj-xhgj-ai-platform
  HostName 192.168.27.77
  User administrator
  RequestTTY yes
  ServerAliveInterval 30
  ServerAliveCountMax 3
  TCPKeepAlive yes
  ExitOnForwardFailure yes
  RemoteForward 7890 192.168.21.108:7890
  RemoteCommand bash -lc 'cd ~/projects/ai/java/xhgj-ai-platform && exec /home/linuxbrew/.linuxbrew/bin/zellij attach -c proj-xhgj-ai-platform'
```

## 诊断解释框架

* 如果日志稳定出现 `Received disconnect ... disconnected by user`，优先怀疑客户端、终端、VS Code Remote SSH 或本地网络主动关闭。
* 如果断开前后出现 `timeout`、`broken pipe`、`reset by peer`，优先看网络链路、Windows 睡眠/省电、NAT/防火墙空闲超时。
* 如果断联通常发生在十几分钟后，优先使用近 24 小时到近 7 天历史日志统计，并围绕具体断开时间点做前后 2-5 分钟切片；实时 `journalctl -f` 只适合作为第二轮验证。
* 如果出现 kex 阶段关闭、`MaxStartups`、大量短连接或认证中连接，优先看 VS Code Remote SSH 多连接、客户端重连风暴或服务端连接限流。
* 如果远端 `7890` 没有 `sshd` 监听或监听归属异常，优先验证 `RemoteForward` 是否失败、端口是否被旧会话占用、`ExitOnForwardFailure` 是否生效。
* 如果存在多个来自同一客户端的 SSH 连接同时配置 `RemoteForward 7890`，优先拆分 Host：VS Code 使用不带 `RemoteCommand` / `RemoteForward` 的 Host，人工 zellij 连接使用带转发和 attach 的 Host。
* 如果断开后 zellij session 仍在，说明 zellij 服务端 session 本身较稳定；需要继续看 attach 客户端为何退出。
* 如果命令行 `ssh -vvv` 稳定而 VS Code Remote SSH 不稳定，优先拆分 VS Code 使用的 Host 配置，避免 `RemoteCommand` 干扰 VS Code 的非交互连接。
