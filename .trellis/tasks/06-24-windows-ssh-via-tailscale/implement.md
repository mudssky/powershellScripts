# Implement: Windows-over-Tailscale SSH 配置入库

## 实现顺序

依赖关系决定顺序：先模板（被脚本引用）→ 脚本（被测试引用）→ 测试 → 规范 → 文档扩写 → QA。

### Step 1 — 模板目录 `config/network/openssh/`
- [ ] `sshd_config.example`：按 design 的"加固要点"写，含 Windows `Match Group administrators` 说明注释。
- [ ] `README.md`：目录职责、`.example` 与本机 `sshd_config` 关系、衔接 `scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1`、手动复制命令。
- [ ] `.gitignore`：按 design 的内容。

### Step 2 — 脚本 `scripts/pwsh/network/openssh/Enable-WindowsOpenSsh.ps1`
- [ ] 参数块（`-DefaultShell` / `-Port` / `-SshdConfigSource` / `-SshdConfigTarget` / `-DryRun` / `-SkipSshdConfigApply`）。
- [ ] `Show-Usage`、`Test-IsWindowsPlatform`、`Get-EnablePlan`、`New-SshdConfigBackupName`、`Invoke-EnableStep`。
- [ ] 主入口受 `PWSH_TEST_SKIP_ENABLE_WINDOWS_SSH_MAIN` 保护。
- [ ] 所有公共函数补标准注释（核心功能/入参/返回值），对齐 rathole/start.ps1 注释密度。
- [ ] `Set-StrictMode -Version Latest` + `$ErrorActionPreference = 'Stop'`。

### Step 3 — Pester 测试 `tests/Enable-WindowsOpenSsh.Tests.ps1`
- [ ] `BeforeAll` 设置 `PWSH_TEST_SKIP_ENABLE_WINDOWS_SSH_MAIN=1` 后 dot-source 脚本。
- [ ] 断言点（对齐 TailscaleRatholeStart.Tests.ps1 风格）：
  - `Show-Usage` 含 `Enable-WindowsOpenSsh` 与 `-DryRun`。
  - `Test-IsWindowsPlatform` 在当前平台返回 bool。
  - `New-SshdConfigBackupName` 生成符合 `.*\.\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.bak$` 的名称。
  - `Get-EnablePlan` 含全部步骤且顺序正确（capability → service → autostart → firewall → defaultshell → config）。
  - `Get-EnablePlan` 的 firewall 步骤 `LocalPort` 反映 `-Port` 参数。
  - DefaultShell 不存在时计划标注回退。
  - `-DryRun` 路径不抛错。

### Step 4 — 集成规范 `.trellis/spec/infra/openssh.md` + index 登记
- [ ] 按 rathole.md / hammerspoon-plugins.md 七节结构写。
- [ ] 在 `.trellis/spec/infra/index.md` Guidelines Index 表追加一行。

### Step 5 — 文档扩写（不另起新文件）
- [ ] `docs/cheatsheet/vscode/remote/setup-ssh.md`：补"通过 Tailscale 连 Windows"节，指向脚本与模板，给 `ssh mudssky@ser6pro` / `ssh mudssky@100.64.162.90` 示例。
- [ ] `docs/cheatsheet/network/tailscale/index.md`：在 SSH 段补"Windows 走原生 OpenSSH Server"指向。

## 验证命令

```powershell
# 1. pwsh 测试（AGENTS.md：pwsh 相关改动必须过）
pnpm test:pwsh:all

# 2. 如需显式验证 coverage 门槛
pnpm test:pwsh:coverage

# 3. 根目录 QA（AGENTS.md：代码改动完成时执行）
pnpm qa
```

若本机 Docker 不可用：至少 `pnpm test:pwsh:full`（兼容保留，当前等价 coverage），并在说明里注明 Linux 覆盖依赖 CI/WSL。

## 风险点 / 回滚

- **改 `.trellis/spec/infra/index.md`**：是公共索引表，只追加一行，不动既有行；回滚只需删该行。
- **改两份 cheatsheet**：是扩写不是重写，保留原有内容；回滚按 git 反向 hunk。
- **新增 `config/network/openssh/.gitignore`**：首次新增，无既有内容冲突。
- **脚本只新增不改既有**：不触碰 `Setup-SshNoPasswd.ps1`（客户端脚本，职责不同）。

## 完成前的检查

- [ ] 无真实密钥 / authorized_keys / 本机 sshd_config 被提交（`.gitignore` 生效）。
- [ ] 所有新增 `.ps1` 公共函数有规范注释。
- [ ] `pnpm test:pwsh:all` 通过新增测试。
- [ ] `pnpm qa` 通过。
- [ ] 更新 `prd.md` 的 Acceptance Criteria 勾选状态。
