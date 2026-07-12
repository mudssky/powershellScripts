# Ansible Managed Host Preparation

## Scenario: 三平台 Ansible 首次接管前置准备

### 1. Scope / Trigger

- Trigger: 修改 `linux/bootstrap/prepare-ansible-host.sh`、`macos/bootstrap/prepare-ansible-host.zsh`、`windows/bootstrap/Prepare-WindowsAnsibleHost.ps1`、`WindowsAnsibleHostPreparation.psm1` 或其测试/操作文档。
- Scope: 在被控端本机建立 Ansible 首次连接所需的 Tailscale、SSH、Python、sudo/管理员、service 和 firewall rule 前置；不安装 Ansible，不执行 Stage 0/Stage 1。
- Design intent: 能自动安装的缺失项直接安装；只能由用户完成的登录、设备批准、系统权限、重启或重新登录必须以结构化 `ManualSteps` 返回。

### 2. Signatures

```bash
bash linux/bootstrap/prepare-ansible-host.sh \
  [--apply] [--output-format text|json] [--ssh-port <1..65535>]
```

```zsh
zsh macos/bootstrap/prepare-ansible-host.zsh \
  [--apply] [--output-format text|json] [--ssh-port <1..65535>]
```

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File windows/bootstrap/Prepare-WindowsAnsibleHost.ps1 `
  [-TailscaleIPv4 <100.64.0.0/10 address>] [-SshPort <1..65535>] `
  [-Apply] [-OutputFormat Text|Json] [-SourceRevision <branch|tag|commit>]
```

- 默认 Operation 为 `Preview`；真实写入必须显式 `--apply` / `-Apply`。
- Windows 入口可单文件运行；同目录模块缺失时从公开 GitHub 的 `SourceRevision` 下载依赖到临时缓存。稳定自动化应传具体 commit，控制面继续使用父仓库固定的 submodule gitlink。
- Windows PowerShell 5.1 单文件入口及其完整下载依赖闭包中，只要 `.ps1`/`.psm1` 含非 ASCII 文本就必须使用 UTF-8 BOM；不能只验证入口和第一层模块，否则间接 `Import-Module` 会在非 UTF-8 系统代码页上产生连锁 parser error。

### 3. Contracts

- 统一 document 字段至少包含：`SchemaVersion`、`Platform`、`Operation`、`Status`、`ExitCode`、`HostName`、`UserName`、`TailscaleIPv4`、`SshPort`、`PythonPath`、`Results`、`ManualSteps`、`NextCommands`、`RerunCommand`。
- `Results[]` 字段为 `Name`、`Status`、`ExitCode`、`Changed`、`Message`。
- `ManualSteps[]` 字段为 `Name`、`Location`、`Command`、`VerifyCommand`、`Reason`；Text 与 Json 必须来自同一数据源。
- JSON stdout 只能有一个 document；进度或诊断不得污染 stdout。
- 退出码固定为 `0` 成功/已满足/Preview，`1` 执行或验证失败，`2` 参数无效，`10` 外部 Blocked/RestartRequired。
- 安装矩阵：
  - Debian/Ubuntu：`openssh-server python3 sudo curl`、Tailscale 官方安装脚本、`ssh`/`tailscaled` systemd service。
  - Arch：`openssh python sudo curl`、Tailscale 官方安装脚本、`sshd`/`tailscaled` systemd service。
  - macOS：复用 `macos/01installHomebrew.zsh`，通过 brew 安装 Python 和 Tailscale cask，使用 `systemsetup` 启用 Remote Login。
  - Windows：winget 安装 Tailscale，Windows capability 安装 Microsoft OpenSSH Server，`sshd` Automatic/Running，DefaultShell 为 Windows PowerShell 5.1。
- 不写 SSH 私钥，不覆盖 `sshd_config`/`authorized_keys`/认证策略，不改变防火墙全局开关；活动防火墙只增加对应 Tailscale SSH 例外。
- Tailscale auth key 不属于脚本参数；登录和设备批准通过交互或 GUI 完成。
- zsh 中不得用 `path`、`status` 作为普通局部变量，它们是会影响 `PATH` 或只读状态的特殊变量；Bash 3.2 + `set -u` 遍历可能为空的数组前必须先检查元素数量。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| 默认调用 | Preview/0，零系统写入，列出自动安装计划和未来 ManualSteps |
| SSH port 非 1..65535 | Invalid/2，零系统写入 |
| Windows 显式 IP 不在 100.64.0.0/10 | Invalid/2，零系统状态读取或写入 |
| Linux 为 WSL | Blocked/10，提示优先管理 Windows 宿主或显式设计 WSL 通道 |
| Linux 非 Debian/Ubuntu/Arch | Blocked/10，输出完整手工安装与验证步骤 |
| Apply 无 sudo/管理员权限 | Blocked/10，先输出获得权限的 Location/Command/VerifyCommand |
| Tailscale 安装完成但未登录 | Blocked/10，保留已完成安装并输出登录、验证、重跑步骤 |
| macOS systemsetup 被 Full Disk Access 阻止 | Blocked/10，列出系统设置路径、重开终端和命令 |
| Windows capability 返回 RestartNeeded | RestartRequired/10，不再以 listener 缺失覆盖成 Failed/1 |
| 单文件下载依赖缺少 UTF-8 BOM | 自动化编码断言失败；不得发布给 Windows PowerShell 5.1，避免把错误解码误报为缺少引号或花括号 |
| 防火墙全局关闭 | Skipped，保持关闭 |
| Apply 后 SSH/Python/service 验证失败 | Failed/1，保留已经完成的 Results |

### 5. Good / Base / Bad Cases

- Good: Windows 用户只下载入口 `.ps1`，指定 GitHub commit，脚本自动获取模块、安装 Tailscale/OpenSSH，并在 GUI 登录后重跑到 Succeeded。
- Good: Linux 主机已满足 Python/SSH，仅缺 Tailscale；apply 只安装并启用 Tailscale，然后以 ManualSteps 等待浏览器授权。
- Base: macOS 已安装 Homebrew/Tailscale，但 Remote Login 被系统权限阻止；脚本保留已满足项并返回完整 Full Disk Access 操作。
- Bad: 缺 Tailscale 时只输出“请手工安装”，没有安装命令、操作位置、验证和重跑命令。
- Bad: Windows capability 要求重启后继续把缺少 sshd listener 记为 Failed，丢失真正的恢复动作。
- Bad: 在 zsh 循环中写 `path=...`，导致后续命令报 `command not found`；或遍历空 Bash 数组触发 unbound variable。

### 6. Tests Required

- Vitest：Linux Preview 单文档 JSON、WSL Blocked ManualSteps、macOS Tailscale 登录 ManualSteps。
- Pester：退出码优先级、Windows 缺失项计划、非管理员 Apply、无效 Tailscale IP、非 Windows JSON、单文件入口及完整下载依赖的 UTF-8 BOM、PowerShell parser 和 revision 下载能力。
- Parser：`bash -n`、`zsh -n`；Windows `.ps1`/`.psm1` 必须通过 parser，含中文文件必须保留 UTF-8 BOM。
- Gates：`pnpm qa`、`pnpm test:bash`、`pnpm test:pwsh:all`、`git diff --check`。
- 实机：至少一台 Windows 执行 Preview/Apply、验证 `sshd`/TCP 22，并从另一 tailnet 节点执行 SSH；其余平台按可用机器补充。

### 7. Wrong vs Correct

#### Wrong

```zsh
while IFS= read -r path; do
    git restore -- "$path"
done
```

```bash
for step in "${MANUAL_STEPS[@]}"; do
    ...
done
```

#### Correct

```zsh
while IFS= read -r file_path; do
    git restore -- "$file_path"
done
```

```bash
if [ "${#MANUAL_STEPS[@]}" -gt 0 ]; then
    for step in "${MANUAL_STEPS[@]}"; do
        ...
    done
fi
```

理由：zsh 的 `path` 与 `PATH` 绑定，赋值会破坏命令查找；macOS Bash 3.2 在 `set -u` 下展开从未赋值的空数组会退出。显式避开特殊变量并守卫数组计数，测试和真实入口才能跨平台稳定运行。
