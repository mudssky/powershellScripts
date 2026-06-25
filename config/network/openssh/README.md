# Windows OpenSSH Server 模板

这个目录提供 Windows 版 OpenSSH Server 的 `sshd_config` 加固模板，配合仓库脚本一键启用。
设计目标是“仅经 Tailscale 内网暴露”——密钥登录优先、关闭密码登录、收窄可登录用户范围。

与 `config/network/rathole/`、`config/network/tailscale/derp/` 同属网络集成模板目录。

## 目录职责

| 文件 | 作用 |
|------|------|
| `sshd_config.example` | Windows 加固配置模板，复制到本机 `$env:ProgramData\ssh\sshd_config` 后微调 |
| `.gitignore` | 忽略本机运行态（`sshd_config`、`*.bak`）和真实密钥，不入库 |
| `README.md` | 本文件 |

## 机器侧运行态（不入库）

这些路径都是**本机态**，不进仓库，等同 rathole 的 `*.local.toml`：

- 本机配置：`C:\ProgramData\ssh\sshd_config`
- 普通用户公钥：`C:\Users\<user>\.ssh\authorized_keys`
- 管理员共享公钥：`C:\ProgramData\ssh\administrators_authorized_keys`
- 默认 Shell 注册表：`HKLM:\SOFTWARE\OpenSSH` → `DefaultShell`

## 一键启用（推荐）

用仓库脚本完成安装 capability、起服务、放行防火墙、设置默认 Shell、应用本模板：

```powershell
# 先预览将执行的操作（不改动系统）
./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 -DryRun

# 实际执行（需要管理员权限）
./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1
```

只装服务和防火墙，不改 `sshd_config`：

```powershell
./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 -SkipSshdConfigApply
```

## 手动流程（参考）

不使用脚本时：

```powershell
# 1. 安装 OpenSSH Server（管理员）
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# 2. 放行防火墙（通常安装时自动配置）
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' `
  -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

# 3. 应用配置（覆盖前先备份）
Copy-Item $env:ProgramData\ssh\sshd_config "$env:ProgramData\ssh\sshd_config.bak"
Copy-Item ./config/network/openssh/sshd_config.example $env:ProgramData\ssh\sshd_config
Restart-Service sshd

# 4. 设置默认 Shell（可选，默认为 cmd.exe）
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
  -Value "C:\Program Files\PowerShell\7\pwsh.exe" -PropertyType String -Force
```

## Windows 管理员 authorized_keys 坑

Windows 版 OpenSSH 默认带一段 `Match Group administrators`，会把管理员用户的公钥
重定向到共享文件 `C:\ProgramData\ssh\administrators_authorized_keys`，而不是
`~/.ssh/authorized_keys`。这是 Windows 上 SSH 密钥登录失败的最高频原因。

本模板默认**注释掉**这个 Match 块，让所有用户统一走 `~/.ssh/authorized_keys`。
详情见 `sshd_config.example` 内的注释。

## 经 Tailscale 连接

启用后在另一台 Tailscale 节点测试：

```bash
ssh <用户名>@<机器名>          # 例如 ssh mudssky@ser6pro
ssh <用户名>@100.64.162.90     # 或直接用 tailnet IP
```

注意：Windows 上不推荐使用 `tailscale up --ssh`（Tailscale SSH 对 Windows 支持有限），
主线走原生 OpenSSH Server。

## 验证

```powershell
Get-Service sshd                              # 应为 Running
Get-NetFirewallRule -Name *ssh* | Format-Table # 应有 sshd 规则
```

```bash
# 从另一台 tailnet 节点
ssh -v <用户名>@<机器名>
```
