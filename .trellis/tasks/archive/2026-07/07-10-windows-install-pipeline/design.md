# Windows 安装流水线技术设计

## 目标与边界

本任务把 Windows 接入现有两阶段安装模型。根编排器继续拥有 Core/Full 步骤图、步骤选择和共享 source 恢复；Windows 只拥有 Windows PowerShell 5.1 bootstrap、Scoop/winget、用户字体、PATH、AutoHotkey、提升执行和 WSL 宿主业务。

以下能力不在 Windows 叶子重复实现：

- Core/Full、Step/FromStep/SkipStep、汇总和共享 Auto restore 由根 `install.ps1` 与 `InstallOrchestrator.psm1` 负责。
- CLI 标签筛选和逐项安装结果由 `psutils/modules/install.psm1` 负责。
- Profile、模块、Node/pnpm、bin 和 Node build 主体由 `scripts/pwsh/install/ProfileTools.psm1` 负责。
- 镜像 URL、winget snapshot 和语言生态事务由 package source 配置与现有 helper 负责。
- WSL 发行版内 `/etc/wsl.conf`、Docker 和 Linux Core 继续由 `linux/` 负责。

## 执行流

```text
Windows PowerShell 5.1 -> windows/00quickstart.ps1
  -> detect edition/build/architecture/elevation
  -> download manifest bundle or load local bootstrap assets
  -> preflight missing Git + PowerShell + [Full] AHK + [IncludeWsl] WSL
  -> at most one isolated UAC child
  -> stop with 10 when a machine operation requires restart
  -> refresh PATH, shallow clone or reuse repo
  -> windows/01installScoop.ps1
  -> windows/02installPowerShell.ps1 (normally AlreadyPresent)
  -> pwsh ./install.ps1 -Preset Core|Full ...
       -> 03 winget capability + npm/pnpm/pip/go sources
       -> 04 registry-level Skipped
       -> 05 Scoop Core CLI
       -> 06 Scoop Nerd Fonts
       -> 07 shared Profile/tools + Windows PATH
       -> [Full] 08 Scoop terminal extras
       -> [Full] 09 verify AutoHotkey v2 + user Startup
       -> 10/11 registry-level Skipped
       -> 99 read-only verification
  -> [IncludeWsl] windows/wsl/Initialize-WslHost.ps1 user configuration + handoff
```

00 不保存 Stage 1 步骤列表。它只组合 Stage 0、调用根入口，并在根入口成功后完成显式 WSL 宿主的用户配置与客体移交。需要提升的 WSL 安装已经在根入口之前进入同一个 Stage 0 operation plan。

## 编号、文件与所有权

| 编号 | 逻辑 ID | 标准入口 | 职责 |
|---|---|---|---|
| 00 | bootstrap | `windows/00quickstart.ps1` | PS5.1、Git/PowerShell 安装计划、clone、Stage 1 与可选 WSL |
| 01 | package-manager | `windows/01installScoop.ps1` | 普通用户 Scoop 安装与验证 |
| 02 | pwsh | `windows/02installPowerShell.ps1` | winget/MSI PowerShell 7 安装与验证 |
| 03 | sources | `windows/03configureSources.ps1` | winget capability 与共享语言 source |
| 04 | shell | 不适用 | 由注册表 Skipped |
| 05 | core-cli | `windows/05installCoreCli.ps1` | `Windows + core + cli` Scoop 项 |
| 06 | fonts | `windows/06installFonts.ps1` | JetBrains Mono/Fira Code Nerd Font |
| 07 | profile-tools | `windows/07installProfileTools.ps1` | 公共 Profile Tools 与 Windows PATH |
| 08 | full-apps | `windows/08installFullApps.ps1` | `Windows + cli + terminal-extras` Scoop 项 |
| 09 | platform-automation | `windows/09deployAutoHotkey.ps1` | AutoHotkey v2、构建与用户 Startup |
| 10/11 | login/desktop | 不适用 | 由注册表 Skipped |
| 99 | verify | `windows/99verifyInstall.ps1` | 只读 Text/Json 验证 |

共享与平台模块：

- `windows/bootstrap/WindowsBootstrap.psm1`：PS5.1-compatible 平台探测、下载、签名校验、PATH 刷新和机器操作计划。
- `windows/bootstrap/bootstrap-manifest.psd1`：远程 00 在 clone 前下载的最小资产及 SHA256 清单。
- `windows/bootstrap/Invoke-WindowsElevatedPlan.ps1`：受限 operation allowlist 的提升子进程。
- `windows/pwsh/WindowsInstall.psm1`：Stage 1 平台模型、Scoop/字体/PATH/AHK/WSL 结果与验证 helper。
- `windows/pwsh/Invoke-WindowsSources.ps1`：共享 source 单文档适配。
- `windows/pwsh/Test-InstallState.ps1`：从 catalog 与平台状态生成只读检查。
- `config/install/windows-packages.psd1`：Stage 0 package ID、Scoop bucket、字体与 WSL 默认声明。
- `windows/wsl/.wslconfig`：从 `linux/wsl2/.wslconfig` 迁移的 Windows 用户级模板。

## 平台模型

`Get-WindowsInstallEnvironment` 返回：

```text
Edition: Windows11 | Windows10 | Server | Unknown
BuildNumber: int
Architecture: amd64 | arm64 | unknown
IsServer: bool
IsAdministrator: bool
HasWinget: bool
HasPowerShell7: bool
HasScoop: bool
HasWsl: bool
SupportsModernWslConfig: bool
SupportLevel: Full | Partial | Blocked
```

生产探测读取 Windows NT CurrentVersion registry、`PROCESSOR_ARCHITECTURE`、当前 token 与可执行命令。模块允许通过参数/fixture registry 文件覆盖输入，叶子只消费共享对象。

支持矩阵：

| 环境 | Stage 0/Core | Full/AHK | IncludeWsl | 99 |
|---|---|---|---|---|
| Windows 11 22H2+ x64 | Full | Full | Full | Full |
| Windows 10 22H2 x64 | Full | Full | Partial，跳过 Win11-only 配置 | Full |
| Windows ARM64 | Blocked | Blocked | Blocked | 只读 Blocked |
| Windows Server/CI | WhatIf/Partial | GUI Blocked | Blocked | 平台与 fixture 验证 |
| 非 Windows | Blocked | Blocked | Blocked | fixture 可运行 |

## Stage 0

### 签名

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\00quickstart.ps1 `
  [-RepoUrl <url>] [-RepoDir <path>] [-BootstrapBaseUri <uri>] `
  [-Preset Core|Full] [-NetworkMode Direct|China|Auto] `
  [-GitInstallerPath <exe>] [-PowerShellMsiPath <msi>] `
  [-AutoHotkeyInstallerPath <exe>] [-ScoopInstallerPath <ps1>] `
  [-IncludeWsl] [-WslDistribution <name>] `
  [-Unattended|-NonInteractive] [-WhatIf]
```

- 本地仓库直接加载 bootstrap 模块。远程入口先从 `BootstrapBaseUri` 下载 `windows/bootstrap/bootstrap-manifest.psd1`，再把下列相对路径下载到隔离临时目录并按清单 SHA256 校验：
  - `windows/bootstrap/WindowsBootstrap.psm1`
  - `windows/bootstrap/Invoke-WindowsElevatedPlan.ps1`
  - `scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1`
  - `config/network/package-sources.bootstrap.env`
  - `config/install/windows-packages.psd1`
- 00 只硬编码 manifest 的相对路径和默认 `BootstrapBaseUri`；package ID、镜像 URL、字体与 WSL 默认值不在 00 复制。任一资产缺失或 hash 不匹配都在下载、提升和 clone 前返回失败。
- WhatIf 不下载、不安装、不弹 UAC、不 clone、不写 source 或用户配置。
- 已有 repo 只校验 `.git` 与 `install.ps1`；目录存在但不是 clone 返回参数错误。

### 机器安装计划

00 在 clone 前必须完成整次运行的机器级预检。缺失的 Git、PowerShell 7、Full 所需 AutoHotkey v2，以及显式 IncludeWsl 所需的 WSL 安装组成一个 machine operation plan，以保证一次 00 调用最多弹一次 UAC。计划按 Git/PowerShell、AutoHotkey、WSL 顺序执行；任何 operation 失败即停止，WSL 返回 restart required 时不进入 clone 或 Stage 1，重跑会依靠已满足状态跳过前序操作。

优先级：

1. 已安装且验证成功 -> AlreadyPresent。
2. 显式本地 Git installer / PowerShell MSI / AutoHotkey installer -> 校验路径与 Authenticode 后加入计划。
3. winget 可用 -> 通过已下载的 `Invoke-PackageSourceBootstrap.ps1` 包装 `Git.Git`、`Microsoft.PowerShell` 和本次计划中的其他精确 ID 安装。
4. Direct 且 winget 不可用 -> 下载官方签名 Git installer 与 PowerShell x64 MSI。
5. China/Auto 无 winget adapter或本地包 -> Blocked/10。

官方 PowerShell winget 安装使用精确 ID与 source，并接受 source/package agreements。MSI fallback 使用静默 `msiexec`、`ADD_PATH=1`、`USE_MU=1` 与 `ENABLE_MU=1`；具体 installer 类型不依赖 winget 永久保持 MSI，因为 PowerShell 7.6+ 的 winget 默认包形态已变化。

### 提升协议

`Invoke-WindowsElevatedPlan.ps1` 只接受 JSON operation：

- `WingetInstall`
- `MsiInstall`
- `ExeInstaller`
- `WslInstall`

每种 operation 有固定字段和参数 allowlist。普通用户进程写 plan/result 临时文件，通过 `Start-Process powershell.exe -Verb RunAs -Wait` 启动一次子进程。子进程可按 plan 的 `NetworkMode` 调用固定路径的 Stage 0 winget source helper，但不接受任意 helper 或脚本文本；它不调用 Scoop、Profile、bin、Startup 或用户配置脚本。

- `Unattended` 允许这一 UAC。
- `NonInteractive` 只在无需 machine operation 时继续，否则返回 10。
- UAC 取消、result 缺失、operation 失败或重启码均映射为 Blocked/Failed。
- 完成后普通用户进程通过 User + Machine registry PATH 重建 `$env:PATH`，再验证 plan 中每个组件。
- 由 00 启动的 Stage 1 不再允许第二次提升：09 和 WSL 用户阶段若发现对应机器组件仍缺失，返回 Blocked/10 和独立重跑命令。直接独立执行 02、09 或 WSL 入口时，每个入口自身仍可遵循“本次调用最多一次 UAC”的合同。

### Scoop

01 保持普通用户执行。已有 Scoop 只验证；Direct 可使用官方 installer；China/Auto 缺 Scoop 时只接受显式本地 installer 或返回 10，不内嵌镜像 URL。安装后刷新 PATH 并验证 `scoop --version`。

## Stage 1 source

03 返回一个 Windows source document：

- winget：只报告结构化 cmdlet、管理员提升和 snapshot capability；共享 Stage 1 引擎继续返回 Unsupported，不解析 CLI 表格，也不把 winget 纳入根 transaction ID。
- npm、pnpm、pip、go：调用共享 `Switch-Mirrors.ps1`，使用根 transaction ID。
- Direct：全部 no-op/official。
- China：共享 transaction 持久；winget 只在需要执行安装的 Stage 0/独立 Windows 叶子中由 bootstrap helper 包装，并保留首次 snapshot 与 Restore 状态。
- Auto：共享 transaction 由根恢复；需要执行的 winget 命令在 bootstrap helper 内临时切换并恢复。

JSON stdout 只能有一个文档，winget capability 作为 Results 中的组件，不允许 helper 文本混入 stdout。

## 包与预设

### Scoop Core

05 选择 `RequiredTag @('core','cli')`、`TargetOS Windows`。首批为：

```text
zoxide fnm starship fzf ripgrep jq uv bat fd eza
```

缺 Scoop返回 Blocked/10；WhatIf 即使本机无 Scoop也输出 catalog 计划。

### Fonts

06 从 `windows-packages.psd1` 读取 nerd-fonts bucket 与 `JetBrainsMono-NF`、`FiraCode-NF`。bucket add、包安装和验证均幂等。Windows Server/CI 真实写入 Blocked，WhatIf 可输出计划。

### Profile Tools

`ProfileTools.psm1` 扩展 Platform `Windows`：

1. `installModules.ps1 -Platform Windows`。
2. `profile/profile.ps1 -LoadProfile`。
3. fnm Node LTS。
4. 根 packageManager 对应 pnpm。
5. `Manage-BinScripts.ps1 -Action sync -Force`。
6. Node install/build。
7. uv/nbstripout。

Windows 不运行 Unix Bash build。07 追加根目录/bin 的 User PATH 幂等写入与当前进程刷新。共享模块继续返回组件结果，不自行 exit。

### Full

08 只选择 `Windows + cli + terminal-extras` Scoop 项。首版从已与 macOS/Linux 对齐的清单中标记，不把剩余 Scoop 项自动归类。EarTrumpet、Twinkle Tray、Neovide 等 GUI 不进入默认 Full。

### AutoHotkey

09 分两段：

1. 验证 AutoHotkey v2。经 00 进入 Full 时，缺失安装已属于 Stage 0 的一次提升计划；09 不再提升。09 独立执行时才可由 winget catalog 与 bootstrap source wrapper 构造本次调用唯一的提升计划。
2. 普通用户调用重构后的 `scripts/ahk/makeScripts.ps1`，生成组合脚本和当前用户 Startup 快捷方式。

`makeScripts.ps1` 增加 ShouldProcess、结构化结果、可覆盖 Output/Startup 路径和 `-NoAutoStart`。流水线默认可启动生成脚本，但 WhatIf/测试禁止 COM、Startup 和进程启动。`install-autohotkey.ps1` 保留兼容包装，不再 ReadKey。

## WSL 宿主

```powershell
pwsh windows/wsl/Initialize-WslHost.ps1 `
  [-Distribution Ubuntu-24.04] [-WslConfigPath <path>] `
  [-Unattended|-NonInteractive] [-WhatIf]
```

- 未安装 WSL 时，显式 IncludeWsl 才由 00 构造 `wsl --install --no-launch -d <name>` 提升 operation；根 `install.ps1` 不增加 WSL 参数。
- 安装或系统功能要求 reboot 时，00 在 Stage 1 前返回 RestartRequired/10，并给出完整重跑命令。
- `.wslconfig` 从 `linux/wsl2/` 迁到 `windows/wsl/`。`windows-packages.psd1` 为需要版本门槛的键声明 minimum build/capability，用户阶段据此生成有效配置后写入当前普通用户 `%UserProfile%`；内容变化时备份、同目录临时文件、原子替换，返回 10。
- 不执行 `wsl --shutdown`、`--terminate`、`--unregister`。
- WSL 已就绪后输出宿主到 `linux/00quickstart.sh` 的显式 handoff 命令，不在宿主脚本复制 Linux 客体逻辑。

## 验证

```powershell
pwsh windows/99verifyInstall.ps1 `
  [-Preset Core|Full] [-Step <id[]>] [-IncludeWsl] `
  [-OutputFormat Text|Json]
```

结果字段与 Linux 99 对齐：`SchemaVersion`、`Preset`、`Environment`、`Status`、`ExitCode`、`Counts`、`Results`。Failed/1 > Blocked/10 > Succeeded/0；Skipped/Warn 不单独失败。

- Core/Full 软件名从 `profile/installer/apps-config.json` 读取。
- 字体与 WSL 期望从 `windows-packages.psd1` 和模板读取。
- 默认 WSL 缺失为 Skipped；`-IncludeWsl` 或精确 `-Step wsl-host` 时才计为 Blocked/Fail。
- JSON stdout 单文档，诊断写 stderr。

## 测试策略

- 跨平台 unit：平台模型、catalog、退出优先级、提升 plan 校验、PATH 合并、WSL 配置比较。
- Windows CI：远程 manifest bundle、Stage 0 fake winget/MSI/Git/Scoop、Full+IncludeWsl 单次提升计划、叶子 WhatIf、AHK 临时 Startup、99 JSON、根 Core/Full 参数链。
- 非 Windows host：PowerShell parser、catalog、模块 unit；Windows-only 集成按平台 skip。
- 所有测试使用临时 USERPROFILE 与目标路径，绝不执行真实 UAC、安装、字体、COM Startup、AHK 进程或 WSL shutdown。

## 兼容、迁移与回滚

- `install.ps1 -installApp` 保留弃用的显式全量路径，不改变新 Core/Full 范围。
- `profile/installer/installFont.ps1` 与 AHK 旧安装脚本收敛为新模块/叶子的兼容包装。
- `linux/wsl2/.wslconfig` 和 `loadWslConfig.ps1` 移到 `windows/wsl/`，更新有效引用；不把迁移当冷归档。
- source rollback 继续使用 winget bootstrap snapshot 和根 transaction ID。
- 用户 PATH、`.wslconfig` 和 Startup 只在内容变化时写入；可撤销步骤提供明确 Remove/Restore 命令。

## 参考

- PowerShell Windows installation: `https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows`
- WSL basic commands: `https://learn.microsoft.com/windows/wsl/basic-commands`
- WSL configuration: `https://learn.microsoft.com/windows/wsl/wsl-config`
