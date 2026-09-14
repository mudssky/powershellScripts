# WSL ↔ Windows browser-debug 互操作流程

适用于：在 WSL 内创建 Windows 端 debug 浏览器快捷方式、启动/停止调试 Profile、让 WSL 侧工具（Playwright、curl）消费 CDP。

## 事实来源

| 项 | 入口 |
| --- | --- |
| CLI 命令树与平台守卫 | `scripts/pwsh/devops/browser-debug/main.ps1`、`runtime.ps1`（`Assert-BrowserDebugWindowsPlatform`） |
| 快捷方式生成与 Bypass 分支 | `runtime.ps1` `New-BrowserDebugShortcut`（UNC 入口自动追加 `-ExecutionPolicy Bypass`） |
| Profile 克隆语义 | `commands.ps1` `Invoke-BrowserDebugProfileCreate`（默认源 `%LOCALAPPDATA%` 下浏览器 User Data） |
| WSL 交互式入口 | `shell/shared.d/browser-debug.sh`（`browser-debug` 函数） |
| 命令索引 | `docs/scripts-index.md` browser-debug 区块 |

## 直调契约（AI agent 非交互会话使用）

WSL 交互式 shell 的 `browser-debug` 函数不适用于非交互会话；agent 直调等价命令：

```bash
PWSH='/mnt/c/Program Files/PowerShell/7/pwsh.exe'
ENTRY=$(wslpath -w bin/browser-debug.ps1)
"$PWSH" -NoProfile -ExecutionPolicy Bypass \
  -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; & '$ENTRY' profile list --json"
```

硬性约束（全部经实测验证，违反任一条会失败）：

1. **必须 `-ExecutionPolicy Bypass`**：仓库在 WSL 文件系统，Windows 侧入口是 UNC 路径，RemoteSigned 视 UNC 为不可信区域，缺该参数直接报"未数字签名"。
2. **必须 pwsh 7，不回退 Windows PowerShell 5.1**：registry 写入依赖 `Set-Content -Encoding utf8NoBOM` 与 `[System.IO.File]::Move` 三参重载，5.1 会崩。
3. **必须前置 `[Console]::OutputEncoding=UTF8`**：Windows pwsh 对重定向 stdout 默认输出系统 ANSI 代码页（中文系统 GBK），WSL 终端按 UTF-8 解析会乱码。
4. **参数含空格时不得用 `-Command` 尾部透传**：pwsh 按空格分割尾部参数，路径需在 shell 侧按 PowerShell 规则转义（`'` → `''`）后拼入命令串；`-File` 模式无此问题但无法前置编码设置。
5. 探测顺序：`command -v pwsh.exe`（PATH 已含 Windows 路径时）→ `/mnt/c/Program Files/PowerShell/7/pwsh.exe` → `/mnt/c/Program Files/PowerShell/6/pwsh.exe`。

## 标准流程

```bash
# 1. 复制 Chrome User Data 创建调试 Profile（自动生成 Windows 桌面快捷方式并登记 registry）
browser-debug profile create <name> --browser chrome

# 2. 启动（默认 local，CDP 127.0.0.1:<port>；--open-guide 生成指南页，非交互确认需 --yes）
browser-debug profile start <name> --mode local --open-guide --yes

# 3. WSL 内消费 CDP（.wslconfig 需 networkingMode=mirrored + hostAddressLoopback=true）
curl http://localhost:<cdpPort>/json/version

# 4. 停止 / 状态 / 快捷方式补建
browser-debug profile stop <name>
browser-debug profile status <name>
browser-debug profile shortcut <name> --mode lan
```

约束：

- `profile create` 复制真实 Chrome User Data 前会检测浏览器运行状态与锁文件（`Test-BrowserDebugSourceInUse`），Chrome 未完全关闭时拒绝克隆；属预期行为，不绕过。
- registry 默认 `D:\browser-debug-profiles\registry.json`，Profile 数据与日常浏览器隔离；D 盘不存在时按报错显式传 `--registry-path`/`--profile-path`。
- 快捷方式由 Windows 进程内 WScript.Shell COM 生成，入口为 UNC 时已自动携带 Bypass，双击即可启动；本地路径 checkout 场景参数保持原合同（见快捷方式回归测试）。

## 验证命令

```bash
# 交互式入口注册与降级
bash -n shell/shared.d/browser-debug.sh && bash --noprofile -ic 'source shell/shared.d/browser-debug.sh; type browser-debug'

# 直调链路（只读）
browser-debug profile list --json

# 专项测试（windowsOnly 用例需 Windows pwsh；Linux lane 跳过）
pnpm test:pwsh:all
```
