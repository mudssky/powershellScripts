# Windows OpenSSH Server 运维

## 关键路径

- 加固配置模板：`config/network/openssh/sshd_config.example`
- 模板说明：`config/network/openssh/README.md`
- 一键启用脚本：`scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1`
- spec 契约：`.trellis/spec/infra/openssh.md`
- 机器侧运行态（不入库）：
  - 本机配置：`C:\ProgramData\ssh\sshd_config`
  - 普通用户公钥：`C:\Users\<user>\.ssh\authorized_keys`
  - 管理员共享公钥：`C:\ProgramData\ssh\administrators_authorized_keys`
  - 默认 Shell 注册表：`HKLM:\SOFTWARE\OpenSSH` → `DefaultShell`

机器侧运行态与本机密钥绝不入库；`config/network/openssh/.gitignore` 已忽略。

## 服务边界

- 主线是「原生 OpenSSH Server + 仅经 Tailscale 内网暴露」，不用 `tailscale up --ssh`（Windows 支持有限）。
- 模板默认 `PasswordAuthentication no`、`PubkeyAuthentication yes`、`PermitRootLogin no`。
- 模板默认**注释掉** Windows 的 `Match Group administrators` 块，让管理员也走 `~/.ssh/authorized_keys`（这是 Windows SSH 密钥登录失败的最高频原因）。
- 真实配置是本机的 `C:\ProgramData\ssh\sshd_config`，`sshd_config.example` 只是模板；覆盖前必须按 AGENTS.md 生成时间戳 `.bak`。

## 一键启用（推荐）

在目标 Windows 机器上以**管理员**身份执行（从仓库根目录）：

```powershell
# 先预览将执行的操作（不改动系统）
./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 -DryRun

# 实际执行
./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1
```

只装服务/防火墙/DefaultShell，不改 `sshd_config`：

```powershell
./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 -SkipSshdConfigApply
```

自定义端口和默认 Shell：

```powershell
./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 `
  -Port 2222 `
  -DefaultShell "C:\Program Files\PowerShell\7\pwsh.exe"
```

脚本步骤固定且幂等：安装 capability → 起服务 → 开机自启 → 放行防火墙 → 写 DefaultShell → 应用 sshd_config（可选，覆盖前自动 `.bak`）→ 重启 sshd。已完成的步骤重跑无害。

## 已知坑：New-NetFirewallRule -Enabled $true

PowerShell 7 的 NetSecurity 模块用强类型枚举 `[NetSecurity.Enabled]`，参数绑定器**不会**把 `[bool]$true` 转成枚举，会报：

```
Cannot convert value "True" to type
"Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Enabled".
```

PS 5.1 能转，所以老脚本常写成 `-Enabled $true` 而不自知。正确写法是字符串字面量，跨 PS 5.1/7 都兼容：

```powershell
-Enabled 'True'   # 推荐
```

`Enable-WindowsOpenSsh.ps1` 已采用此写法。手动建防火墙规则时同样要这么写。

## 经 Tailscale 连接

启用后在另一台 Tailscale 节点测试（tailnet 内直连，无需端口映射）：

```bash
ssh <用户名>@<机器名>        # 例如 ssh mudssky@ser6pro（MagicDNS 已启用）
ssh <用户名>@100.64.162.90   # 或直接用 tailnet IP
```

若公钥登录失败：先确认公钥已追加到目标用户 `~/.ssh/authorized_keys`；管理员用户还要确认模板已注释 `Match Group administrators`（否则公钥要放 `administrators_authorized_keys`）。

## 常见排查

| 现象 | 排查方向 |
|------|----------|
| 连接超时 | `Get-Service sshd` 是否 Running；`Get-NetFirewallRule -Name *ssh*` 是否存在放行规则 |
| 服务起得来但连不上 | 22 端口监听确认：`Get-NetTCPConnection -LocalPort 22 -State Listen`；IPv4/IPv6 都应监听 |
| `Permission denied (publickey)` | 公钥未加到 `authorized_keys`，或管理员用户被 `Match Group administrators` 重定向到共享文件 |
| `New-NetFirewallRule` 报 `拒绝访问` | 需要管理员权限，非提权 shell 跑不了 |
| 安装后从 tailnet 仍连不上 | 确认两台机器都在同一 tailnet 且对端在线：`tailscale status` |

## 验证清单

在目标 Windows 机器上：

```powershell
Get-Service sshd                                       # 应为 Running
Get-NetFirewallRule -Name *ssh* | Format-Table         # 应有 sshd 规则
Get-NetTCPConnection -LocalPort 22 -State Listen       # IPv4/IPv6 都应 Listen
```

从另一台 tailnet 节点：

```bash
ssh -v <用户名>@<机器名>
```

模板、脚本或文档变更后从仓库根目录运行：

```bash
pnpm qa
```

纯模板/文档类产物不要求新增 Pester 断言；改动启用脚本时可先 `pwsh -NoProfile -File ./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 -DryRun` 确认无错输出完整计划。
