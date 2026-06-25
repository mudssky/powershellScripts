# Windows-over-Tailscale SSH 配置入库

## Goal

把"在 Windows 机器上启用 OpenSSH Server 并通过 Tailscale 远程连接"这件事，按仓库已有的 `config/network/<service>/` + `scripts/pwsh/network/<service>/` + `docs/cheatsheet/` 三段式约定做成可复用产物，与 `config/network/rathole/`、`config/network/tailscale/derp/` 同等规格。

直接动因来自会话 `sess_877d81d6`：目标机 `ser6pro` (100.64.162.90) 已在 Tailscale 网络且 MagicDNS 已启用，但本机 OpenSSH Server 未安装、22 端口未放行，无法 `ssh mudssky@ser6pro`。

## Confirmed Facts（来自代码库与会话）

- `sshd` 服务在本机不存在，`Add-WindowsCapability` 需管理员权限。
- 机器侧运行态不入库：`C:\ProgramData\ssh\sshd_config`、`C:\Users\mudssky\.ssh\authorized_keys`、`HKLM:\SOFTWARE\OpenSSH` 都是本机态，对应 rathole 的 `*.local.toml`，必须被 `.gitignore` 忽略。
- 仓库对网络集成有一致的三段式分层：
  - 模板 + `.local` + `start.ps1` → `config/network/<service>/`
  - 维护脚本 → `scripts/pwsh/network/<service>/`
  - 速查文档 → `docs/cheatsheet/network/<service>/` 或 `docs/cheatsheet/vscode/remote/`
  - 集成规范 → `.trellis/spec/infra/<service>.md`（rathole/derp/self-hosted 等 13 篇）
- SSH 相关仓库已存在的产物（避免重复）：
  - `docs/cheatsheet/vscode/remote/setup-ssh.md`：已有全平台"被控端开启 SSH 服务"步骤（含 Windows capability 安装）。
  - `docs/cheatsheet/network/tailscale/index.md` 第 7 节：已有 `tailscale up --ssh` 段落（Linux，非 Windows）。
  - `scripts/pwsh/devops/Setup-SshNoPasswd.ps1`：已有**客户端**密钥分发脚本（生成密钥、追加公钥、写 `~/.ssh/config`）。
- Windows OpenSSH 有专属坑：默认 `sshd_config` 含 `Match Group administrators` 把 admin 的 `authorized_keys` 重定向到 `C:\ProgramData\ssh\administrators_authorized_keys`，普通用户的 `~/.ssh/authorized_keys` 才按常规路径生效。

## Requirements

### R1 模板目录 `config/network/openssh/`
- `sshd_config.example`：面向 Windows 的加固模板（密钥登录优先、禁 root、限制可登录用户范围、明确处理 admin `authorized_keys` 路径差异）。
- `README.md`：说明目录职责、`.example` 与本机 `sshd_config` 的关系、与 `scripts/pwsh/network/openssh/` 的衔接。
- `.gitignore`：忽略本机态 `sshd_config`、`authorized_keys`、备份、私钥。

### R2 一键启用脚本 `scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1`
- 安装 OpenSSH Server capability、启动 `sshd` 并设开机自启。
- 放行防火墙 22 端口。
- 设置 `DefaultShell`（默认 `pwsh.exe`，可覆盖）。
- 应用 `sshd_config.example` 到本机前，按 `AGENTS.md` 规则在本机 `sshd_config` 同目录创建带可读时间戳的 `.bak`。
- `-DryRun` 只打印计划，不执行系统改动（对齐 rathole/start.ps1 的可测试性约定）。
- 支持 `-DefaultShell`、`-Port`、`-SshdConfigPath` 等覆盖参数。
- 非 Windows 平台明确报错退出。

### R3 集成规范 `.trellis/spec/infra/openssh.md`
- 与 `rathole.md` / `self-hosted-compose.md` 同规格：含 Scope/Trigger、Signatures、Contracts、Validation & Error Matrix、Good/Base/Bad、Tests Required、Wrong vs Correct。
- 在 `.trellis/spec/infra/index.md` 的 Guidelines Index 表登记新行。

### R4 文档（扩写已有，不另起新文件）
- `docs/cheatsheet/vscode/remote/setup-ssh.md`：补一节"通过 Tailscale 连 Windows"，指向本仓库脚本与模板，给出 `ssh mudssky@ser6pro` / `ssh mudssky@100.64.162.90` 示例。
- `docs/cheatsheet/network/tailscale/index.md`：在 SSH 段补充 Windows 走原生 OpenSSH Server（而非 Tailscale SSH，因 Windows 支持有限）的指向。

### R5 Pester 测试（脚本逻辑部分）
- `Enable-WindowsOpenSsh.ps1` 的纯逻辑函数（路径解析、`.bak` 命名、计划生成、参数校验）必须有 Pester 覆盖；`-DryRun` 路径必须在 host 与 Linux Pester 下通过（对齐 rathole 约定，不要求真实 capability 安装）。

## Acceptance Criteria

- [ ] `config/network/openssh/` 存在且含 `sshd_config.example`、`README.md`、`.gitignore`。
- [ ] `Enable-WindowsOpenSsh.ps1 -DryRun` 输出完整计划（capability 安装、服务启动、防火墙、DefaultShell、sshd_config 应用 + `.bak`），不实际改动系统。
- [ ] 非 Windows 平台调用脚本时明确报错退出。
- [ ] 改动本机 `sshd_config` 的路径在脚本里走时间戳 `.bak`，命名格式符合 `AGENTS.md`。
- [ ] `docs/cheatsheet/vscode/remote/setup-ssh.md` 与 tailscale 速查各补一节指向仓库产物。
- [ ] `.trellis/spec/infra/openssh.md` 存在并在 `index.md` 登记新行。
- [ ] `pnpm test:pwsh:all`（或按 AGENTS.md 等价路径）通过新增/受影响测试。
- [ ] `pnpm qa` 通过。

## Out of Scope

- 不实现 `tailscale up --ssh`（Tailscale SSH）在 Windows 上的落地——官方 Windows 支持有限，主线走原生 OpenSSH Server。
- 不入库任何真实密钥、真实 `authorized_keys`、本机 `sshd_config` 运行态。
- 不为 Linux/macOS 被控端新建脚本（已有 setup-ssh.md 覆盖，客户端密钥分发已有 `Setup-SshNoPasswd.ps1`）。
- 不做基于 AD/域账号的 SSH 集成、不做非 22 端口的 SELinux/seport 处理。

## Open Questions

（无，范围已全部确定。）
