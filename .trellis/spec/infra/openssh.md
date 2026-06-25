# OpenSSH Server (Windows) spec

> 本规范记录 `config/network/openssh/` 的 Windows 版 OpenSSH Server 模板、
> `scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1` 的启用流程、本机运行态与机器配置边界。
> 修改 sshd_config 模板、启用脚本或相关文档时必须先阅读。

---

## Scenario: Windows OpenSSH Server 启用与 Tailscale 远程连接

### 1. Scope / Trigger

- Trigger: 修改 `config/network/openssh/**`、`scripts/pwsh/network/openssh/**`，或更新 Windows SSH 启用/连接相关 cheatsheet。
- Scope: 仓库提供 Windows `sshd_config` 加固模板 + 一键启用脚本；机器侧运行态不入库。
- Design intent: 主线是“原生 OpenSSH Server + 仅经 Tailscale 内网暴露”，不使用 `tailscale up --ssh`（Windows 支持有限）。密钥登录优先、关闭密码登录，把被控端攻击面压到最小。

### 2. Signatures

- 文件路径：
  - `config/network/openssh/sshd_config.example`
  - `config/network/openssh/README.md`
  - `config/network/openssh/.gitignore`
  - `scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1`
- 启用脚本：
  - `./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 -DryRun`
  - `./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1`
  - `./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 -SkipSshdConfigApply`
  - `./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 -Port 2222 -DefaultShell "C:\Program Files\PowerShell\7\pwsh.exe"`
- 机器侧运行态（不入库）：
  - `C:\ProgramData\ssh\sshd_config`
  - `C:\Users\<user>\.ssh\authorized_keys`
  - `C:\ProgramData\ssh\administrators_authorized_keys`
  - `HKLM:\SOFTWARE\OpenSSH` → `DefaultShell`

### 3. Contracts

- Local config contract:
  - `sshd_config.example` 是模板；真实配置是本机的 `C:\ProgramData\ssh\sshd_config`，由 `.gitignore` 忽略。
  - 覆盖本机 `sshd_config` 前必须在同目录生成 `<base>.<YYYY-MM-dd_HH-mm-ss>.bak`（遵守 AGENTS.md 时间戳备份规则）。
  - 真实 `authorized_keys`、host key、私钥绝不入库。
- Script contract:
  - `Enable-WindowsOpenSsh.ps1` 必须支持 `-DryRun`，零副作用预览计划。
  - 主入口受 `PWSH_TEST_SKIP_ENABLE_WINDOWS_SSH_MAIN` 环境变量保护，允许 dot-source 时只加载函数。
  - 步骤顺序固定：安装 capability → 起服务 → 开机自启 → 防火墙 → DefaultShell → 应用 sshd_config（可选）。
  - 非 Windows 平台必须明确报错退出。
  - `DefaultShell` 路径在本机不存在时回退到 `powershell.exe`，并在计划中标注回退。
- sshd_config 模板 contract:
  - 默认 `PasswordAuthentication no`、`PubkeyAuthentication yes`、`PermitRootLogin no`。
  - 默认注释掉 Windows 的 `Match Group administrators` 重定向块，让管理员也走 `~/.ssh/authorized_keys`（避免最高频的 Windows SSH 坑）。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| 非 Windows 平台运行脚本 | throw 明确错误并退出 |
| `sshd_config.example` 缺失 | throw，列出找不到的模板路径 |
| `-DryRun` | 只打印计划，不调用任何系统 cmdlet |
| 本机 `sshd_config` 已存在且应用模板 | 覆盖前生成时间戳 `.bak` |
| 本机 `sshd_config` 不存在（首次安装） | 直接写入，不生成 `.bak` |
| `$DefaultShell` 路径不存在 | 回退到 `powershell.exe` 并发 Warning |
| `-SkipSshdConfigApply` | 跳过配置应用与备份步骤，只装服务/防火墙/Shell |
| 安装后 `sshd` 服务存在 | 应用配置后自动 `Restart-Service sshd` |

### 5. Good/Base/Bad Cases

- Good: `ssh mudssky@ser6pro` 经 Tailscale 直连成功，密钥登录，密码登录关闭。
- Good: 管理员用户把公钥放进 `~/.ssh/authorized_keys` 即可生效，因为模板注释了 `Match Group administrators`。
- Base: `Enable-WindowsOpenSsh.ps1 -DryRun` 输出完整计划，用于人工核对后再实际执行。
- Bad: 把本机 `C:\ProgramData\ssh\sshd_config` 或真实 `authorized_keys` 提交进仓库。
- Bad: 应用模板时不打 `.bak`，丢失本机原有配置。
- Bad: 在 Windows 上引导用户走 `tailscale up --ssh`，官方 Windows 支持有限且偏离原生 OpenSSH 主线。
- Bad: 保留 `Match Group administrators` 重定向却没在文档/模板里说明，导致管理员用户配了 `~/.ssh/authorized_keys` 登不上。

### 6. Tests Required

- 配置/文档/脚本属于模板类产物，不要求新增 Pester 断言。
- 手动验证：
  - `pwsh -NoProfile -File ./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 -DryRun` 必须无错输出完整计划。
  - dot-source 脚本（设 `PWSH_TEST_SKIP_ENABLE_WINDOWS_SSH_MAIN=1`）后 `Resolve-SshdPaths` / `New-SshdConfigBackupName` 可独立调用。
- 实际部署后验证：`Get-Service sshd`（Running）、`Get-NetFirewallRule -Name *ssh*`、从另一台 tailnet 节点 `ssh -v <user>@<host>`。
- 修改脚本后执行根目录 `pnpm qa`。

### 7. Wrong vs Correct

#### Wrong

```powershell
# 直接覆盖本机配置，丢失原有内容，也无备份。
Copy-Item .\sshd_config.example C:\ProgramData\ssh\sshd_config -Force
```

问题：覆盖前无备份，本机原有 sshd_config 自定义全部丢失；且路径硬编码、无 DryRun 预览。

#### Correct

```powershell
./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1 -DryRun
./scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1
```

理由：DryRun 先预览；实际执行时覆盖前按 AGENTS.md 生成时间戳 `.bak`；步骤幂等且顺序固定。
