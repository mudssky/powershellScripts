# 三平台 Ansible 被控端准备脚本

## Goal

提供可在目标机本地执行的三平台准备入口，把 Linux、macOS、Windows 主机准备到可由 `self-hosted-compose` 中 Ansible control plane 首次接管的状态，并输出可供人工或后续自动化解析的检查结果。

## Background

- 控制端可能是 Linux、macOS、Windows WSL2，或通过 VS Code Remote SSH 登录的 Linux；本任务不在控制端安装 Ansible，也不增加定时运行。
- Linux/macOS 正式连接使用 SSH；Windows 首次连接使用 Microsoft OpenSSH，后续由既有 `Enable-WindowsRemotePsRemoting.ps1` 切换到 PSRP HTTPS。
- Windows 目标机 `iminipro820` 已接入 Tailscale，地址为 `100.125.34.90`，用户为 `mudssky`，当前没有 `sshd`。
- 官方 Ansible 文档要求 Unix managed node 具备受支持的 Python；Windows SSH 应使用系统 capability 提供的 Microsoft OpenSSH，并推荐将 `DefaultShell` 设为 Windows PowerShell 5.1。
- 仓库已有 OpenSSH 加固模板和人工启用脚本，但准备阶段不能在尚未配置公钥时覆盖认证配置或关闭密码登录。

## Requirements

### R1 统一调用与结果合同

- 新增以下入口：
  - `linux/bootstrap/prepare-ansible-host.sh`
  - `macos/bootstrap/prepare-ansible-host.zsh`
  - `windows/bootstrap/Prepare-WindowsAnsibleHost.ps1`
- 三个平台默认只生成 Preview，不修改系统；真实变更必须显式使用 `--apply` 或 `-Apply`。
- 支持 Text 和 Json 输出；JSON stdout 必须只有一个 document。
- 统一输出至少包含 `SchemaVersion`、`Platform`、`Operation`、`Status`、`ExitCode`、`HostName`、`UserName`、`TailscaleIPv4`、`SshPort`、`PythonPath`、`Results` 和 `RerunCommand`。
- 退出码固定为：`0` 成功、已满足或 Preview；`1` 执行/验证失败；`2` 参数或平台输入错误；`10` 外部权限、交互登录或人工操作导致的 Blocked。
- 重复 apply 必须幂等，已满足的 capability、package、service 和配置不得重复修改。

### R2 公共安全边界

- 准备入口只负责建立 Ansible 首次连接所需的本机前置，不执行 Stage 0/Stage 1 软件安装，不运行 Ansible playbook。
- Tailscale 做安装状态、运行状态和唯一 `100.64.0.0/10` IPv4 检查；缺失时由脚本使用各平台官方安装路径自动安装。
- 无法可靠无交互完成的登录、GUI/系统权限授权、重启或重新登录必须返回 `Blocked/10`，并在 `ManualSteps` 中给出操作位置、完整命令、验证命令和重跑命令。
- 不自动使用 Tailscale auth key；安装后未登录时引导用户执行交互式 `tailscale up` 或平台 GUI 登录。
- 不修改任何平台防火墙的全局启用/关闭状态。
- 不写入 SSH 私钥，不自动生成或分发控制端私钥。
- 不覆盖现有 `sshd_config`、`authorized_keys` 或认证策略；SSH 加固和公钥分发由后续 Ansible role 处理。
- 所有真实系统变更前先完成参数、平台、权限和 Tailscale 地址预检，避免部分写入。

### R3 Linux 准备

- 支持仓库既有范围内的 Ubuntu/Debian 与 Arch Linux；其他发行版返回 `Blocked/10`。
- 检查当前用户、非交互 sudo、唯一 Tailscale IPv4、SSH 端口、Python 3 和 systemd/OpenRC 可用性。
- apply 时按发行版安装缺失的 `openssh-server`、`python3`、`sudo` 和 Tailscale，启用并启动 `ssh`/`sshd` 与 `tailscaled` 服务。
- WSL 客体不作为独立 SSH 被控端自动启用服务；检测到 WSL 时返回 `Blocked/10`，提示从宿主或显式设计的 WSL 通道管理。

### R4 macOS 准备

- 检查当前用户、sudo、唯一 Tailscale IPv4、Remote Login 状态和 Python 3。
- apply 时使用系统 `systemsetup` 启用 Remote Login，不修改 macOS Application Firewall。
- Python 3 已存在时直接复用；缺失时通过 Homebrew 安装 `python`。
- Homebrew 缺失时，apply 复用仓库既有 `macos/01installHomebrew.zsh` 安装，再安装 `python` 和 Tailscale cask；需要用户确认 sudo 时允许终端交互。
- Tailscale 安装后需要 GUI/System Extension/登录确认时返回 `Blocked/10`，列出打开 App、批准系统扩展、登录和验证地址的完整步骤。
- 若 `systemsetup` 因 Full Disk Access 或其他 macOS 权限策略拒绝执行，返回 `Blocked/10` 并给出可操作提示。

### R5 Windows 准备

- 入口兼容 Windows PowerShell 5.1，含中文字符串的 `.ps1` 使用 UTF-8 BOM。
- Preview 可在非管理员进程中生成；apply 必须在管理员 PowerShell 中执行，不请求 UAC。
- 检查 `mudssky` 当前身份及本地 Administrators 组成员关系、唯一 Tailscale IPv4、`OpenSSH.Server~~~~0.0.1.0` capability、`sshd` 服务、TCP 22 和 DefaultShell。
- apply 时安装缺失的 Microsoft OpenSSH Server capability，将 `sshd` 设置为 Automatic 并启动，把 `HKLM:\SOFTWARE\OpenSSH\DefaultShell` 设置为 `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`。
- Tailscale 缺失时优先使用 `winget install --id Tailscale.Tailscale --exact`；winget 不可用时返回 `Blocked/10`，给出官方下载安装和 GUI 登录步骤。
- 不调用现有 OpenSSH 加固脚本的防火墙或 `sshd_config` 覆盖路径；不改变已有端口、listener 和认证配置。
- 防火墙开启时只报告现有 OpenSSH rule 是否可能放行；防火墙关闭时保持关闭。脚本不得声称 TCP 22 只监听 Tailscale，因为 Windows OpenSSH 默认可能监听所有接口。
- 成功结果给出 `ssh mudssky@100.125.34.90` 和后续 PSRP bootstrap 的建议命令。

### R6 验证与文档

- 为三平台结果聚合、参数校验、Preview 零写入、平台计划和关键 Blocked 分支增加自动化测试。
- shell 入口通过 `bash -n` / `zsh -n`；Windows 入口通过 PowerShell parser 和 UTF-8 BOM 检查。
- 文档说明三平台本地执行命令、Windows `iminipro820` 首次操作、apply 后从控制端验证 SSH 的步骤。

## Acceptance Criteria

- [x] 三个平台都有默认 Preview、显式 apply 的准备入口，并遵守统一 JSON/退出码合同。
- [x] Linux 能为 Ubuntu/Debian 与 Arch 生成正确 package/service 计划，WSL 和未知发行版明确 Blocked。
- [x] macOS 能检查/启用 Remote Login，并正确处理 Python、Homebrew和 Full Disk Access 分支。
- [x] Windows 能检测并安装 Microsoft OpenSSH Server、启动和自启 `sshd`、设置 PowerShell 5.1 DefaultShell。
- [x] 所有平台验证唯一 Tailscale IPv4；缺失时自动安装 Tailscale，无法自动登录时给出完整人工步骤。
- [x] 结构化结果包含 `ManualSteps`，每个外部 Blocked 都能按步骤操作并得到精确重跑命令。
- [x] 准备流程不修改防火墙全局状态、SSH 认证配置、私钥或现有 `sshd_config`。
- [ ] JSON stdout 可直接解析为一个 document，第二次 apply 不产生无意义变更。
- [x] `pnpm qa`、`pnpm test:pwsh:all`、shell parser 和 `git diff --check` 通过。
- [ ] 在 `iminipro820` 上先 Preview、再管理员 apply，最后从控制端成功执行 `ssh mudssky@100.125.34.90`。

## Out of Scope

- 安装操作系统、PXE、WinPE、Autounattend、云主机创建。
- 在被控端安装或运行 Ansible、配置定时任务或常驻 agent。
- 自动使用 Tailscale auth key、自动批准设备或管理 tailnet ACL。
- SSH 公私钥生成、私钥同步、凭据仓库写入和密码轮换。
- 覆盖 `sshd_config`、关闭密码登录或完成最终 SSH 加固。
- Windows PSRP listener 创建；继续由既有远程 PSRP bootstrap 负责。
