# Windows 安装指南

Windows 新机流程分为 Stage 0 与 Stage 1。首期完整支持 Windows 11 22H2+ x64 和 Windows 10 22H2 x64；ARM64 返回 Blocked/10，Windows Server/CI 只承诺 WhatIf、fixture 与只读验证。

## 推荐入口

从普通用户 Windows PowerShell 5.1 执行，不要预先“以管理员身份运行”：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\00quickstart.ps1 `
  -Preset Core `
  -NetworkMode Direct
```

Stage 0 会预检 Git、PowerShell 7，以及 Full/WSL 可选机器组件，把缺失项合并为最多一次 UAC。提升子进程只执行固定 allowlist operation；Scoop、Profile、用户 PATH、AutoHotkey Startup 和 `.wslconfig` 始终由普通用户进程处理。

远程新机可先下载最小入口，再由入口按 manifest 下载并校验其余 bootstrap 资产：

```powershell
$entry = Join-Path $env:TEMP 'powershellScripts-00quickstart.ps1'
Invoke-WebRequest `
  -Uri 'https://raw.githubusercontent.com/mudssky/powershellScripts/master/windows/00quickstart.ps1' `
  -UseBasicParsing `
  -OutFile $entry

powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entry -Preset Core
```

远程 clone 默认使用 `--depth=1`。已有开发 clone 只复用，不 pull，也不改变 shallow 状态。

## Core 与 Full

Core 安装以下 Scoop CLI：

```text
zoxide fnm starship fzf ripgrep jq uv bat fd eza
```

Full 在 Core 上追加已明确标记的 terminal extras，以及 AutoHotkey v2 和仓库 `scripts/ahk` 当前用户 Startup。EarTrumpet、Twinkle Tray、Neovide、PowerToys 和其他 GUI 不属于默认 Full。

```powershell
# 预览
powershell.exe -NoProfile -File .\windows\00quickstart.ps1 -Preset Full -WhatIf

# 执行
powershell.exe -NoProfile -File .\windows\00quickstart.ps1 -Preset Full
```

Stage 1 也可在已完成 Stage 0 的仓库中独立运行：

```powershell
pwsh .\install.ps1 -Preset Core -WhatIf
pwsh .\install.ps1 -Preset Full -NetworkMode Direct
pwsh .\install.ps1 -Preset Core -Step core-cli
pwsh .\install.ps1 -Preset Core -FromStep profile-tools
```

## 网络模式

- `Direct`：使用现有或官方 source，不创建 source 事务。
- `China`：winget 机器安装通过 Stage 0 helper 保存首次 snapshot；语言生态使用持久事务并提供 Restore 命令。
- `Auto`：仅在官方端点不可用时临时切换；winget helper 和根 source 事务分别负责恢复。

China/Auto 的 winget 修改要求管理员子进程可使用 `Microsoft.WinGet.Client` 的结构化 source cmdlets。条件不满足时返回 Blocked/10，不解析 `winget source list` 表格，也不静默回退 Direct。Scoop 缺失时，China/Auto 需要显式 `-ScoopInstallerPath`。

## 独立入口

| 编号 | 入口 | 职责 |
|---|---|---|
| 00 | `windows/00quickstart.ps1` | PS5.1 bootstrap、一次 UAC、shallow clone 与 Stage 1 移交 |
| 01 | `windows/01installScoop.ps1` | 当前用户 Scoop |
| 02 | `windows/02installPowerShell.ps1` | PowerShell 7 winget/MSI 安装与验证 |
| 03 | `windows/03configureSources.ps1` | winget 只读状态与语言生态 source 事务 |
| 05 | `windows/05installCoreCli.ps1` | 10 个 Core Scoop CLI |
| 06 | `windows/06installFonts.ps1` | JetBrains Mono/Fira Code Nerd Font |
| 07 | `windows/07installProfileTools.ps1` | Profile、Node/pnpm、bin、构建与用户 PATH |
| 08 | `windows/08installFullApps.ps1` | Full terminal extras |
| 09 | `windows/09deployAutoHotkey.ps1` | AutoHotkey v2、聚合脚本与用户 Startup |
| 99 | `windows/99verifyInstall.ps1` | Core/Full 只读 Text/JSON 验证 |

04、10、11 由步骤注册表标记为 Windows 不支持，不创建空脚本。所有写入入口支持 `-WhatIf`。退出码为：成功/已满足/预览 0、执行失败 1、参数错误 2、Blocked 或需要重启 10。

## WSL 宿主

WSL 仅在 00 显式传入 `-IncludeWsl` 时启用，不属于默认 Core/Full：

```powershell
powershell.exe -NoProfile -File .\windows\00quickstart.ps1 `
  -Preset Core `
  -IncludeWsl `
  -WslDistribution Ubuntu-24.04
```

`.wslconfig` 写入 `%UserProfile%\.wslconfig`。内容变化时先创建 `.yyyy-MM-dd_HH-mm-ss.bak`，再同目录替换并返回 10。流水线绝不自动执行 `wsl --shutdown`；请保存 WSL 工作后手工执行，再用相同参数重跑。

Windows 10 只生成满足 build/capability 门槛的设置；Windows 11 22H2+ 使用完整模板。WSL 客体内的 `/etc/wsl.conf`、Docker 和 Linux Core 继续由 `linux/` 流水线负责。

## 验证

```powershell
pwsh .\windows\99verifyInstall.ps1 -Preset Core
pwsh .\windows\99verifyInstall.ps1 -Preset Full -OutputFormat Json
pwsh .\windows\99verifyInstall.ps1 -Preset Core -Step sources
pwsh .\windows\99verifyInstall.ps1 -Preset Core -IncludeWsl
```

JSON stdout 只有一个文档。验证不安装软件、不请求 UAC、不写字体、Startup 或 WSL 配置。

## Windows 11 Core 手工 smoke

首轮自动化只证明 fixture、WhatIf 和只读合同。真实干净 Windows 11 机器后续按以下清单验证：

- 从普通用户 Windows PowerShell 启动远程 Core 命令。
- 确认 Git 与 PowerShell 缺失时整次调用只出现一次 UAC。
- 确认仓库使用 shallow clone，Stage 1 自动接管。
- 重新打开普通用户 `pwsh`，确认 10 个 Core CLI、两种字体、Profile 和仓库 `bin` PATH。
- 执行 `windows/99verifyInstall.ps1 -Preset Core -OutputFormat Json`，确认单文档和退出码。
- 人工取消 UAC、使用 `-NonInteractive`、制造 PATH 未刷新场景，确认均返回可操作的 Blocked/10 和重跑位置。

本仓库当前没有记录这项真实运行态 smoke 已完成，不能用 CI 结果替代。
