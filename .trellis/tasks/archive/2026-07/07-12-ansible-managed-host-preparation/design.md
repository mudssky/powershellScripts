# 三平台 Ansible 被控端准备设计

## 1. 边界与目录

三个本机入口拥有平台检测和最小系统变更，现有 Stage 0/Stage 1 与 Ansible control plane 保持不变：

```text
linux/bootstrap/prepare-ansible-host.sh
macos/bootstrap/prepare-ansible-host.zsh
windows/bootstrap/Prepare-WindowsAnsibleHost.ps1
```

准备完成后的调用链为：

```text
本机准备脚本 -> SSH 首次连接 -> Windows PSRP bootstrap（仅 Windows）
             -> Ansible Stage 0/Stage 1 -> 99 结构化验证
```

## 2. 公共接口

Unix 参数：

```text
--apply
--output-format text|json
--ssh-port <1..65535>
```

Windows 参数：

```powershell
[-Apply] [-OutputFormat Text|Json] [-SshPort <1..65535>]
[-TailscaleIPv4 <100.64.0.0/10 address>]
[-InventoryHost <ansible inventory alias>]
```

默认 Operation 为 `Preview`，显式 apply 为 `Apply`。结果项使用 `Name`、`Status`、`ExitCode`、`Message`、`Changed`；顶层按 `Failed/1 > Blocked/10 > Succeeded/0` 聚合。

JSON stdout 只承载结果 document；进度和诊断写 stderr，避免控制端解析污染。
Windows stderr 使用固定五阶段：预检、安装依赖、配置服务、配置访问、验证。长耗时 capability 安装在系统 `Operation` 进度条出现前输出具体操作、常见耗时，并在完成后输出实际耗时。

## 3. 预检与写入顺序

所有平台先执行零副作用预检：

1. 参数和平台。
2. apply 权限。
3. Tailscale CLI、daemon 和唯一 CGNAT IPv4。
4. 当前 SSH/Python/service 状态。
5. 生成完整 action plan。

脚本可以为缺失项生成并执行安装计划。若安装完成后仍需要 tailnet 登录、系统授权、重启或重新登录，则保留已完成安装，返回 Blocked 并输出全部人工步骤。

## 4. Linux adapter

- 从 `/etc/os-release` 解析 Debian/Ubuntu 或 Arch family。
- Debian 使用 `apt-get update` 与 `apt-get install -y openssh-server python3 sudo curl ca-certificates`，Tailscale 复用官方 `https://tailscale.com/install.sh`。
- Arch 使用 `pacman -Syu --needed --noconfirm openssh python sudo curl ca-certificates`，Tailscale 复用官方安装脚本支持的仓库配置，避免部分升级。
- 通过 `systemctl enable --now ssh|sshd` 管理服务；服务名按已存在 unit 和发行版 family 选择。
- Tailscale 安装后启用 `tailscaled`；未登录时输出 `sudo tailscale up`、浏览器授权和 `tailscale ip -4` 验证步骤。
- `sudo -n true` 是非交互接管能力的硬检查。脚本由 root 执行时视为满足。
- WSL 不自动创建独立 SSH 管理面，返回 Blocked。

## 5. macOS adapter

- Remote Login 状态由 `/usr/sbin/systemsetup -getremotelogin` 读取，apply 使用 `sudo /usr/sbin/systemsetup -setremotelogin on`。
- Python 优先选择 `/usr/bin/python3`，其次选择 PATH 中的 `python3`。
- Python 缺失且 `brew` 已存在时执行 `brew install python`；Homebrew 缺失时复用 `macos/01installHomebrew.zsh`。
- Tailscale 缺失时使用 `brew install --cask tailscale`，随后打开 `/Applications/Tailscale.app`；系统扩展批准与账号登录作为 ManualSteps。
- `systemsetup` 权限拒绝映射为 Blocked，不把 Full Disk Access 问题误报成普通执行失败。

## 6. Windows adapter

- 使用 `Get-WindowsCapability -Online -Name OpenSSH.Server*` 判断 capability；只接受系统 capability，不下载 Win32-OpenSSH。
- 安装后重新读取 `sshd`，设置 `StartupType=Automatic` 并启动。
- DefaultShell 固定为 Windows PowerShell 5.1，确保首次 Ansible SSH 路径与官方支持合同一致。
- Tailscale 缺失时使用 winget 安装；安装器需要重启或 GUI 登录时输出对应 ManualSteps。
- 只读取防火墙 profile/rule 和 TCP listener，不创建、删除或启用 rule，也不覆盖 `sshd_config`。
- Windows 无 Python 要求，`PythonPath` 输出为 null；正式 PSRP 管理由既有 bootstrap 接管。
- `AnsibleControllerConfig` 将实机状态映射为 `self-hosted-compose` 使用的 inventory alias、`windows`/`powershell_scripts_targets` 分组、公开 host vars、首次 SSH 连接变量、私有凭据键和控制端顺序命令；只有 Tailscale、OpenSSH、sshd 与 listener 全部满足时 `Ready=true`。
- sshd apply 先解析 `SetAutomatic`/`Start` 操作；已经 Automatic/Running 时只返回 `AlreadyPresent/Changed=false`，不重复调用 service 写命令。

## 7. Tailscale 发现

- 显式 IP 优先；否则调用 Tailscale CLI 获取 IPv4。
- 只接受唯一 `100.64.0.0/10` IPv4，拒绝 LAN、loopback、IPv6、多地址歧义。
- Linux/macOS 从 PATH 查找 `tailscale`；macOS另检查 App bundle CLI 路径；Windows 同时检查 PATH 和标准安装路径。
- Linux 可执行交互式 `tailscale up`；macOS/Windows 默认引导 GUI 登录。脚本不接受或持久化 auth key。
- `ManualSteps` 每项包含 `Name`、`Location`、`Command`、`VerifyCommand` 和 `Reason`，Text/Json 使用同一数据源。

## 8. 复用策略

- 复用既有 Windows bootstrap 的管理员判断与 Tailscale IPv4 校验思想，但不让新入口依赖 Stage 0 模块的包清单。
- 不直接调用旧 `Enable-WindowsOpenSsh.ps1`，因为该脚本还拥有防火墙和 `sshd_config` 变更，超过本任务安全边界。
- Unix 两个平台共享 JSON schema 和状态词，但保留独立 shell 实现，避免为三个短入口增加新的跨语言 runtime。

## 9. Rollback

- Preview 无副作用。
- SSH/Python package 安装不提供自动卸载，避免删除用户已有依赖。
- 服务启用可由用户按输出命令手工关闭；脚本不自动回滚已成功的基础能力。
- Windows DefaultShell 可删除注册表值恢复 `cmd.exe`，但不会作为失败时自动 rollback，以免改变已建立的 SSH 会话假设。
- 任何失败都在 Results 中保留已完成步骤，便于人工决定恢复或重跑。
