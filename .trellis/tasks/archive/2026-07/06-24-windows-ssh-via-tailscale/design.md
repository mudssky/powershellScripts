# Design: Windows-over-Tailscale SSH 配置入库

## Architecture & Boundaries

严格沿用仓库网络集成的三段式分层，与 `config/network/rathole/`、`config/network/tailscale/derp/` 同构：

```
config/network/openssh/                        # 模板 + 文档 + gitignore（本机运行态）
  ├─ sshd_config.example                        # Windows 加固配置模板
  ├─ README.md                                  # 目录职责、与本机 sshd_config 的关系
  └─ .gitignore                                 # 忽略本机运行态

scripts/pwsh/network/openssh/
  └─ Enable-WindowsOpenSsh.ps1                  # 一键启用：capability/服务/防火墙/DefaultShell/配置应用

tests/
  └─ Enable-WindowsOpenSsh.Tests.ps1            # 纯逻辑 Pester 测试

.trellis/spec/infra/
  └─ openssh.md                                 # 集成规范（与 rathole.md 同规格）
  + index.md                                    # 追加登记行

docs/cheatsheet/vscode/remote/setup-ssh.md      # 扩写：Tailscale 连 Windows 段
docs/cheatsheet/network/tailscale/index.md      # 扩写：Windows 走原生 OpenSSH 段
```

### 边界原则（复用 rathole 契约）

- **机器侧运行态不入库**：`C:\ProgramData\ssh\sshd_config`、`administrators_authorized_keys`、`~/.ssh/authorized_keys`、私钥、`*.bak` 都是本机态，等同 rathole 的 `*.local.toml`，由 `.gitignore` 忽略。
- **仓库只提供可复制模板**：`sshd_config.example` 是"复制 → 本机微调 → 应用"的起点，不直接是运行配置。
- **脚本只做幂等启用 + 可 DryRun 预览**：真正改系统前先用 `-DryRun` 看计划，测试侧只覆盖纯逻辑函数。

## Enable-WindowsOpenSsh.ps1 设计

### 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `-DefaultShell` | `C:\Program Files\PowerShell\7\pwsh.exe` | 注册到 `HKLM:\SOFTWARE\OpenSSH\DefaultShell`；缺失时回退到 `powershell.exe` |
| `-Port` | `22` | 防火墙放行端口；同时用于计划输出 |
| `-SshdConfigSource` | `<scriptdir>../../../../config/network/openssh/sshd_config.example` | 模板来源（相对脚本位置解析，避免依赖 cwd） |
| `-SshdConfigTarget` | `$env:ProgramData\ssh\sshd_config` | 本机运行态路径 |
| `-DryRun` | 开关 | 只打印计划，不执行系统改动 |
| `-SkipSshdConfigApply` | 开关 | 跳过配置应用步骤（只装服务+防火墙+shell） |

### 模块结构（对齐 rathole/start.ps1）

- `Show-Usage`：返回用法字符串。
- `Test-IsWindowsPlatform`：用 `$IsWindows`（pwsh 7+）判断；非 Windows 直接 throw。
- `Get-EnablePlan`：纯函数，返回步骤对象数组（capability 安装、`Start-Service`、`Set-Service`、防火墙规则、DefaultShell 注册表写入、配置应用 + `.bak`）。DryRun 和测试都消费它的输出。
- `New-SshdConfigBackupName`：按 `AGENTS.md` 生成 `<base>.<YYYY-MM-DD_HH-mm-ss>.bak`。纯函数，便于测试。
- `Invoke-EnableStep`：执行单个步骤（DryRun 时只打印）。
- 主入口：受 `PWSH_TEST_SKIP_ENABLE_WINDOWS_SSH_MAIN` 环境变量保护，dot-source 时不执行。

### 步骤计划对象（Get-EnablePlan 输出）

```powershell
@(
  [pscustomobject]@{ Step='InstallCapability'; Cmd='Add-WindowsCapability'; Args=@('-Online','-Name','OpenSSH.Server~~~~0.0.1.0'); Idempotent=$true }
  [pscustomobject]@{ Step='StartService';      Cmd='Start-Service';        Args=@('-Name','sshd') }
  [pscustomobject]@{ Step='AutoStartService';  Cmd='Set-Service';          Args=@('-Name','sshd','-StartupType','Automatic') }
  [pscustomobject]@{ Step='FirewallAllow';     Cmd='New-NetFirewallRule';  Args=@('-Name','sshd','-DisplayName','OpenSSH Server (sshd)','-Enabled',$true,'-Direction','Inbound','-Protocol','TCP','-Action','Allow','-LocalPort',$Port) }
  [pscustomobject]@{ Step='SetDefaultShell';   Cmd='Set-ItemProperty';     Args=@('-Path','HKLM:\SOFTWARE\OpenSSH','-Name','DefaultShell','-Value',$DefaultShell) }
  [pscustomobject]@{ Step='ApplySshdConfig';   Cmd='<copy template + bak>'; ... }
)
```

### `.bak` 契约（遵守 AGENTS.md）

应用 `sshd_config.example` 到本机前：
1. 若本机 `sshd_config` 已存在，在**同目录**生成 `<basename>.<YYYY-MM-DD_HH-mm-ss>.bak`（注意是 `-` 不是 `:`，可读且 Windows 文件名安全）。
2. `.bak` 文件本身也必须在仓库 `.gitignore` 里（本机态）。

## sshd_config.example 内容要点

面向 Windows 的加固默认值：

- `Port 22`
- `PubkeyAuthentication yes`
- `PasswordAuthentication no`（默认关密码登录，靠密钥；与 Tailscale-only 暴露面配合）
- `PermitRootLogin no`（Windows 无 root，但保留语义明确）
- `AllowUsers` 留注释占位，由本机微调
- Windows 专属：保留并说明 `Match Group administrators` → `administrators_authorized_keys` 的重定向行为，避免 admin 用户配了 `~/.ssh/authorized_keys` 却不生效
- 顶部注释说明这是模板，复制到 `$env:ProgramData\ssh\sshd_config` 后按本机调整

## openssh.md 规范要点（与 rathole.md 同构）

7 节：Scope/Trigger、Signatures、Contracts、Validation & Error Matrix、Good/Base/Bad、Tests Required、Wrong vs Correct。

关键契约：
- `sshd_config` 本机态必须 `.gitignore`，真实密钥/authorized_keys 不入库。
- 脚本 `ApplySshdConfig` 步骤必须先打时间戳 `.bak`。
- `-DryRun` 必须可零依赖预览。
- 非平台 throw 必须明确。

Validation Matrix 覆盖：capability 已装、sshd 已运行、防火墙规则已存在、DefaultShell 路径无效、模板缺失、非 Windows 平台。

## .gitignore 内容

```
# 本机 sshd 运行态配置，含可能的服务器特定策略，不应提交。
sshd_config
sshd_config.local
*.bak

# 真实 authorized_keys / host keys / 用户私钥绝不入库。
authorized_keys
administrators_authorized_keys
*_key
*.pem
id_*
```

## 兼容性 & 风险

- **管理员权限**：`Add-WindowsCapability` / `Start-Service` / 注册表写都需要管理员。脚本在非提权会话执行时由底层 cmdlet 自然报错；DryRun 不受影响（纯计划）。
- **`$IsWindows`**：pwsh 7+ 内置。Windows PowerShell 5.1 没有，但仓库脚本约定走 pwsh 7（见 rathole/Setup-SshNoPasswd），用 `[System.Environment]::OSVersion.Platform` 兜底判断以兼容。
- **DefaultShell 路径**：pwsh 不存在时回退 `powershell.exe`，并在计划里标注回退。
- **Tailscale SSH**：不在 Windows 上做（官方支持有限）；文档里明确指引走原生 OpenSSH Server。

## 不做的（重申，避免范围爬升）

- 不实现 `tailscale up --ssh` 落地。
- 不做 Linux/macOS 被控端脚本（setup-ssh.md 已覆盖）。
- 不入库任何真实凭据。
