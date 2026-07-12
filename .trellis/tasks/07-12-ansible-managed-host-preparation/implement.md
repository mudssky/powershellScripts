# 实施计划

## 1. 公共合同与测试夹具

- [x] 固定三平台 schema、状态、退出码和 Text/Json 输出字段。
- [x] 增加 fixture 环境变量或可注入命令路径，使 Linux/macOS 计划测试不执行真实 sudo、包管理器、service 或 Tailscale。
- [x] 增加 Windows 纯计划函数和可注入状态，使 Pester 可测试 Preview 与计划函数。

## 2. Linux 入口

- [x] 新增 `linux/bootstrap/prepare-ansible-host.sh`。
- [x] 实现参数、发行版、WSL、sudo、Tailscale、Python、SSH package/service 检查。
- [x] 实现 Debian/Ubuntu 和 Arch apply adapter，自动安装 Tailscale/SSH/Python/sudo 并保证 package/service 幂等。
- [x] 实现 Text/Json 单文档输出和精确重跑命令。

## 3. macOS 入口

- [x] 新增 `macos/bootstrap/prepare-ansible-host.zsh`。
- [x] 实现 sudo、Tailscale、Remote Login、Python/Homebrew 检查。
- [x] apply 时启用 Remote Login；复用现有 Stage 0 自动补 Homebrew，再安装 Python 和 Tailscale。
- [x] 将 Full Disk Access 等权限拒绝映射为 Blocked/10。

## 4. Windows 入口

- [x] 新增 Windows PowerShell 5.1 兼容的 `windows/bootstrap/Prepare-WindowsAnsibleHost.ps1`。
- [x] 实现管理员和 Administrators 组、Tailscale、capability、service、listener、DefaultShell、防火墙状态检查。
- [x] apply 时通过 winget 自动补 Tailscale，并安装 Microsoft OpenSSH Server、设置 Automatic/Running 和 Windows PowerShell 5.1 DefaultShell。
- [x] 输出 `iminipro820` 的 SSH 验证命令与下一阶段 PSRP bootstrap 命令。
- [x] 确保文件为 UTF-8 BOM，不触碰 `sshd_config` 和防火墙全局状态。

## 5. 自动化测试

- [x] Pester 覆盖结果聚合、唯一 Tailscale IPv4、Windows capability/service/DefaultShell 计划、非管理员 apply 和 JSON 单文档。
- [x] shell 测试覆盖 Linux 发行版 adapter、WSL Blocked、macOS Remote Login/Python 分支和默认 Preview 零写入。
- [x] 执行 `bash -n linux/bootstrap/prepare-ansible-host.sh`。
- [x] 执行 `zsh -n macos/bootstrap/prepare-ansible-host.zsh`。
- [x] 执行 PowerShell parser 与 UTF-8 BOM 断言。

## 6. 文档与实机命令

- [x] 更新远程装机 research/使用文档，记录三平台本机准备命令。
- [x] 为 `iminipro820` 给出管理员 PowerShell Preview、Apply、服务验证和控制端 SSH 命令。
- [x] 明确 TCP 22 默认可能监听 LAN 与 Tailscale，准备脚本不声明 Tailscale-only。

## 7. 质量门

- [x] 运行目标窄测。
- [x] 运行 `pnpm qa`。
- [x] 运行 `pnpm test:pwsh:all`。
- [x] 运行 `git diff --check` 和 `git status --short`。
- [ ] 用户在 `iminipro820` 上完成 Preview；真实 apply 和跨机 SSH 作为实机验收，不在 macOS 控制端伪造。

## 风险与恢复点

- macOS `systemsetup` 可能受 Full Disk Access 限制，必须保留 Blocked 提示，不能反复重试或绕过系统策略。
- Windows capability 安装依赖 Windows Update/Features on Demand；失败时保留原系统状态并输出 DISM/capability 诊断。
- 不调用旧 OpenSSH 加固入口，避免覆盖认证配置后失去首次连接通道。
- 不自动使用 Tailscale auth key；需要账号授权时通过 ManualSteps 引导交互登录，避免把 auth key 引入公开仓库或命令历史。
