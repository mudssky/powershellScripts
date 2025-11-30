## 目标
- 在项目根目录新增 `Setup-SshNoPasswd.ps1`（PowerShell 7+ 跨平台），一键完成 Windows/macOS/Linux 到目标主机的 SSH 免密登录配置，并为 VSCode 提供可用的 `~/.ssh/config` 条目。

## 功能概览
- 自动检测本机系统（`$IsWindows/$IsLinux/$IsMacOS`）。
- 若不存在密钥则生成（默认 `ed25519`，可选 `rsa`），路径默认 `~/.ssh/id_ed25519`。
- 将本机公钥安全追加到目标主机 `~/.ssh/authorized_keys` 并设置权限（`700 ~/.ssh`、`600 authorized_keys`）。
- Linux 服务器可选开关：检查并启动 `sshd`，提示防火墙放行 22 端口（不强制安装）。
- macOS 服务器可选开关：开启“远程登录”（如需，执行前提示并征求同意）。
- 生成 VSCode 兼容的 `~/.ssh/config` 条目（`Host` 别名、`HostName`、`User`、`IdentityFile`、`Port`）。
- 幂等：重复运行不重复写入、权限/配置只在缺失时修复。
- 支持 `-DryRun`（仅展示预执行操作）、`-Verbose`（详细日志）。

## 参数设计
- `-RemoteHost`：目标主机 IP/域名（必填）。
- `-Username`：目标主机登录用户（必填）。
- `-Port`：SSH 端口，默认 `22`。
- `-KeyType`：`ed25519|rsa`，默认 `ed25519`。
- `-KeyPath`：密钥路径，默认 `~/.ssh/id_ed25519` 或随 `-KeyType` 变更。
- `-Alias`：`~/.ssh/config` 中的 `Host` 别名，默认 `ssh-{RemoteHost}`。
- `-ManageServer`：是否执行服务器侧检查（权限、服务状态），默认 `true`（提示并可交互跳过）。
- `-DryRun`：仅打印预执行计划。

## 与现有脚本的关系
- 现有 `Setup-VSCodeSSH.ps1` 使用 `RSA` 并偏向 Windows；新脚本将统一为跨平台与 `ed25519` 优先的实现，保留旧脚本不动，并在文档中推荐使用新脚本。

## Plan
- [ ] **Impact Analysis (影响面分析)**
  - 修改/新增文件：`Setup-SshNoPasswd.ps1`、`docs/cheatsheet/vscode/ssh_nopasswd.md`（追加“一键脚本”章节）
  - 潜在风险：
    - 目标服务器无 `sshd` 或防火墙拦截导致失败
    - 用户主机缺失 `ssh`/`ssh-keygen`（仅提示安装，不强制）
- [ ] **Step 1: Context Gathering**
  - 确认现有 `Setup-VSCodeSSH.ps1` 功能与风格（已对齐）
  - 对照文档 `ssh_nopasswd.md` 的步骤与术语
- [ ] **Step 2: Implementation**
  - 新增 `Setup-SshNoPasswd.ps1`：
    - `[CmdletBinding()]` + `param()`，中文 DocStrings
    - OS 识别与依赖检查（`Get-Command ssh/ssh-keygen`）
    - 密钥生成（默认 `ed25519`，无密码短语；可自定义路径/类型）
    - 公钥追加到远端：
      - 优先使用 `ssh-copy-id`（在 Linux/macOS 常见）
      - 回退：以 `ssh` 远程执行 `mkdir/chmod/echo >> authorized_keys`（确保转义与权限）
    - 修正服务器权限与（可选）服务状态
    - 写入 `~/.ssh/config` 条目（避免重复）
    - `-DryRun`/`-Verbose` 支持，错误时抛出可追踪上下文
- [ ] **Step 3: Verification**
  - 冒烟测试：
    - 本地：若 `-DryRun`，检查所有路径与命令渲染是否正确
    - 远端：`ssh -o BatchMode=yes -p {Port} {User}@{Host} true` 验证免密是否可用
  - 文档更新：在 `ssh_nopasswd.md` 追加“使用脚本”小节与常见报错排查

## 交付物
- 新增：`Setup-SshNoPasswd.ps1`（根目录）
- 文档：在 `docs/cheatsheet/vscode/ssh_nopasswd.md` 增补脚本用法示例

## 后续可选增强
- 支持多主机批量配置（从 JSON/CSV 读取）
- 支持自动检测并提示远端防火墙开放

请确认以上方案，确认后我将实现脚本与文档更新，并进行本地可执行的冒烟验证。