# macOS 首次无人值守安装边界

## 结论

`NONINTERACTIVE=1` 只能消除 Homebrew 安装器自身的确认提示，不能为一个尚未授权的普通用户创造 sudo、设备注册或 macOS 隐私权限。个人新机最实际的目标是“一次管理员认证后无人值守完成 Core”；从开箱、Setup Assistant 到 Full 桌面权限全部零交互，需要 MDM/Automated Device Enrollment 等设备管理前置，不属于普通仓库脚本单独可解决的问题。

## 官方安装器证据

2026-07-10 检查 Homebrew 官方 `install.sh` HEAD 与 Context7 官方文档：

- `NONINTERACTIVE=1` 或 `CI=1` 会关闭安装确认，并且非 TTY stdin 默认也进入 non-interactive。
- non-interactive 模式检查 sudo 时使用 `sudo -n`，不会询问密码；若当前账号没有已缓存的 sudo 凭据、passwordless sudo 或受控 `SUDO_ASKPASS`，安装器会以“Need sudo access on macOS”中止。
- Homebrew 在默认 prefix 创建目录、修改权限、写 `/etc/paths.d/homebrew` 等环节需要 sudo；安装完成后普通 brew 使用通常不再需要 sudo。
- 当 Command Line Tools 缺失时，安装器会先通过 `softwareupdate` 搜索并安装最新 CLT，再执行 `xcode-select --switch`；只有 headless 安装失败且存在 TTY 时，才回退到会弹 GUI 的 `xcode-select --install`。
- 如果已安装完整 Xcode 但尚未接受 license，安装器会中止并要求用户打开 Xcode 或运行 `sudo xcodebuild -license`。
- Homebrew 官方当前要求 macOS Sonoma 14 或更高、受支持 CPU、CLT/Xcode 与 bash；实施时应再次按目标版本核对。

## 三种自动化等级

### Level 1：默认交互首次安装

- 用户运行 `00bootstrap.zsh`。
- 脚本在需要时允许 Homebrew、sudo、CLT GUI fallback 和系统权限提示。
- 适合普通个人设备，成功率最高，但不是无人值守。

### Level 2：一次认证后无人值守 Core

- 启动时通过 `sudo -v` 获取一次管理员认证，并在 bootstrap 期间保持 sudo timestamp；密码不写入脚本、文件、参数或环境变量。
- 随后以 `NONINTERACTIVE=1` 运行 Homebrew 安装器，允许其通过 `softwareupdate` headless 安装 CLT。
- Stage 1 的 package/source/PowerShell/shell/CLI/fonts/Profile/tools 使用非交互参数和确定性失败策略。
- 若 headless CLT、Xcode license、cask pkg 或其他系统前置仍需要交互，立即报告 `Blocked`，而不是挂起等待不可见输入。
- 这是个人配置仓库推荐支持的“首次近似无人值守”模式。

### Level 3：开箱起完全零交互

- 设备必须在脚本运行前由 MDM/Automated Device Enrollment 或受控镜像完成账号、管理员权限、网络、证书、sudo/执行身份和必要系统配置预置。
- CLT、Xcode license、Homebrew prerequisites 可由设备管理任务预装，随后以受控用户身份运行仓库 bootstrap。
- Hammerspoon Accessibility、System Events Automation 等 Full 桌面权限需要 MDM PPPC 等配置策略；普通 shell 脚本不能可靠静默授予自身 TCC 权限。
- 不应把管理员密码硬编码到仓库、`SUDO_ASKPASS` 脚本、环境变量或命令行；也不应为方便而配置无限制 `NOPASSWD: ALL`。
- 仓库可以提供 MDM-friendly 的 non-interactive contract 和退出码，但不负责搭建设备注册与 MDM 控制面。

## 建议接口

- `00bootstrap.zsh` 默认交互运行。
- `00bootstrap.zsh --unattended` 表示 Level 2：允许开头一次 `sudo -v`，之后禁止任何隐藏提示。
- `00bootstrap.zsh --non-interactive` 表示严格零提示：首先执行 `sudo -n true` 和前置检查，不满足即快速失败；用于 MDM/CI/已预置机器。
- `--unattended` 与 `--non-interactive` 都默认执行 Core；Full 必须显式选择，并在没有 PPPC/TCC 前置时允许返回 `Blocked`。
- 严格模式必须在执行前验证：管理员/sudo、CLT headless 条件、网络模式、磁盘空间、架构、macOS 版本和目标目录权限。

## 安全边界

- 永不读取、保存或回显管理员密码。
- 不自动写入宽泛 sudoers 规则。
- 不使用普通脚本绕过 macOS TCC、Gatekeeper 或系统完整性保护。
- 后台执行必须保留结构化日志、步骤状态和明确退出码；失败后可从步骤级重跑。
