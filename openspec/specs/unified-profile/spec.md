# ADDED Requirements

### Requirement: 统一入口加载

`profile.ps1` SHALL 作为所有平台（Windows/Linux/macOS）的统一 Profile 入口脚本。脚本 SHALL 通过 PowerShell 内置变量 `$IsWindows`/`$IsLinux`/`$IsMacOS` 识别当前平台并执行对应的平台特定逻辑。

#### Scenario: Windows 平台加载

- **WHEN** 在 Windows 平台执行 `profile.ps1`
- **THEN** 脚本 SHALL 初始化 sccache（如已安装）、加载所有通用模块和别名、显示加载耗时

#### Scenario: Linux 平台加载

- **WHEN** 在 Linux 平台执行 `profile.ps1`
- **THEN** 脚本 SHALL 执行 `Sync-PathFromBash`、检测 Linuxbrew PATH、初始化 fnm（如已安装）、加载所有通用模块和别名、显示加载耗时

#### Scenario: macOS 平台加载

- **WHEN** 在 macOS 平台执行 `profile.ps1`
- **THEN** 脚本 SHALL 初始化 fnm（如已安装）、加载所有通用模块和别名、显示加载耗时

### Requirement: 向后兼容 shim

`profile_unix.ps1` SHALL 保留为薄 shim 脚本，将所有参数透传到 `profile.ps1`。

#### Scenario: 通过 profile_unix.ps1 加载

- **WHEN** 用户的 `$PROFILE` 指向 `profile_unix.ps1` 并启动 PowerShell
- **THEN** SHALL 透传所有参数并执行 `profile.ps1`，行为与直接调用 `profile.ps1` 完全一致

### Requirement: Set-PowerShellProfile 函数

脚本 SHALL 提供 `Set-PowerShellProfile` 函数用于将 Profile 路径写入 `$PROFILE` 配置文件。该函数 SHALL 在写入前确保目标目录存在，并在写入成功后输出确认信息。

#### Scenario: 首次安装 Profile

- **WHEN** 用户调用 `./profile.ps1 -LoadProfile`
- **THEN** SHALL 调用 `Set-PowerShellProfile` 将当前脚本路径写入 `$PROFILE`，确保目录存在

#### Scenario: 覆盖已有 Profile

- **WHEN** `$PROFILE` 文件已存在且用户调用 `-LoadProfile`
- **THEN** SHALL 备份现有文件（带时间戳后缀 `.bak`）后再写入新内容

### Requirement: 统一 Show-MyProfileHelp

`Show-MyProfileHelp` 函数 SHALL 在 Full 与 Minimal 模式下显示完整信息段，并在 UltraMinimal 模式下提供可降级提示输出。

#### Scenario: Full 或 Minimal 模式显示完整帮助

- **WHEN** 当前模式为 Full 或 Minimal 且用户执行 `Show-MyProfileHelp`
- **THEN** SHALL 依次显示所有 6 个信息段（自定义别名、自定义函数别名、自定义函数包装、核心管理函数、关键环境变量、用户级持久环境变量）

#### Scenario: UltraMinimal 模式降级帮助输出

- **WHEN** 当前模式为 UltraMinimal 且用户执行 `Show-MyProfileHelp`
- **THEN** SHALL 输出模式与最小能力提示，且不因未加载模块而报错

### Requirement: 统一工具初始化

`Initialize-Environment` 函数 SHALL 维护统一的工具初始化表，并依据当前模式控制初始化范围。每个工具的初始化逻辑 SHALL 内部判断平台适用性。

#### Scenario: Full 模式初始化完整工具链

- **WHEN** 当前模式为 Full 且工具已安装
- **THEN** SHALL 执行 starship、zoxide、fnm、sccache 等初始化逻辑，并按平台规则完成配置

#### Scenario: 通用工具初始化

- **WHEN** starship 或 zoxide 已安装
- **THEN** SHALL 在所有平台上初始化该工具，使用 `Invoke-WithFileCache` 缓存初始化脚本

#### Scenario: 平台特定工具初始化

- **WHEN** 在 Windows 平台且 sccache 已安装
- **THEN** SHALL 设置 `$env:RUSTC_WRAPPER = 'sccache'`
- **WHEN** 在 Unix 平台且 fnm 已安装
- **THEN** SHALL 执行 `fnm env --use-on-cd | Out-String | Invoke-Expression`

#### Scenario: Minimal 模式跳过交互增强

- **WHEN** 当前模式为 Minimal
- **THEN** SHALL 跳过工具初始化和别名注册，但保留模块函数可用性

#### Scenario: UltraMinimal 模式仅保留最小能力

- **WHEN** 当前模式为 UltraMinimal
- **THEN** SHALL 跳过模块加载、工具初始化、代理检测、PATH 同步、别名与包装函数注册，仅保留 UTF8 设置、`POWERSHELL_SCRIPTS_ROOT` 与基础变量兼容

### Requirement: 模块化入口编排

`profile.ps1` 在完成拆分后 SHALL 继续作为统一入口，并以可维护的模块化方式组织内部实现。

#### Scenario: 入口路径保持不变

- **WHEN** 用户执行 `./profile/profile.ps1`
- **THEN** 系统 SHALL 通过统一入口完成初始化，且不要求用户修改现有调用方式

### Requirement: 模块加载顺序可控

拆分后的实现 SHALL 采用确定性的 dot-source 顺序加载核心模块与功能模块，以避免函数未定义和作用域初始化错误。

#### Scenario: 核心模块先于功能模块

- **WHEN** profile 启动并开始加载内部脚本
- **THEN** 系统 SHALL 先加载模式决策与基础工具模块，再加载依赖这些能力的功能模块

### Requirement: 模式语义在拆分后保持一致

在模块化拆分后，`Full/Minimal/UltraMinimal` 的模式决策优先级与行为边界 SHALL 与拆分前一致。

#### Scenario: Full 模式优先级保持

- **WHEN** 设置 `POWERSHELL_PROFILE_FULL=1`
- **THEN** 系统 SHALL 强制使用 Full 模式并覆盖其他模式开关

#### Scenario: Minimal 模式手动触发保持

- **WHEN** 设置 `POWERSHELL_PROFILE_MODE=minimal`
- **THEN** 系统 SHALL 进入 Minimal 模式并保持“跳过工具与别名”的语义

#### Scenario: UltraMinimal 自动降级保持

- **WHEN** 命中 `CODEX_THREAD_ID` 或 `CODEX_SANDBOX_NETWORK_DISABLED`
- **THEN** 系统 SHALL 自动进入 UltraMinimal 模式，并保持最小初始化路径

### Requirement: 对外函数兼容可用

拆分后 `Show-MyProfileHelp`、`Initialize-Environment`、`Set-PowerShellProfile` SHALL 继续可用，并保持原有职责。

#### Scenario: 关键函数仍可调用

- **WHEN** profile 加载完成后用户调用关键函数
- **THEN** 系统 SHALL 成功执行函数且不因内部文件拆分而报函数不存在

### Requirement: 模式解析优先级与自动降级

`profile/profile.ps1` SHALL 按固定优先级解析运行模式，优先级为 `POWERSHELL_PROFILE_FULL` > `POWERSHELL_PROFILE_MODE` > `POWERSHELL_PROFILE_ULTRA_MINIMAL` > 自动判定 > 默认值。

#### Scenario: Full 开关最高优先级

- **WHEN** `POWERSHELL_PROFILE_FULL=1` 且同时设置了其他模式变量
- **THEN** 系统 SHALL 强制使用 Full 模式并忽略其他模式变量

#### Scenario: 显式模式变量生效

- **WHEN** `POWERSHELL_PROFILE_MODE` 设置为 `full`、`minimal` 或 `ultra`
- **THEN** 系统 SHALL 使用对应模式并记录来源为显式配置

#### Scenario: UltraMinimal 显式开关生效

- **WHEN** `POWERSHELL_PROFILE_ULTRA_MINIMAL=1` 且未设置 `POWERSHELL_PROFILE_FULL=1`
- **THEN** 系统 SHALL 使用 UltraMinimal 模式

#### Scenario: Codex 或沙盒环境自动降级

- **WHEN** 未设置显式模式变量且检测到 `CODEX_THREAD_ID` 或 `CODEX_SANDBOX_NETWORK_DISABLED`
- **THEN** 系统 SHALL 自动降级为 UltraMinimal 模式

#### Scenario: 默认使用 Full

- **WHEN** 未命中任何显式配置与自动降级条件
- **THEN** 系统 SHALL 使用 Full 模式

### Requirement: 模式诊断摘要输出

模式决策过程 SHALL 提供可观测的诊断摘要，至少包含 `mode`、`source`、`reason`、`markers` 字段，用于说明最终模式与判定依据。

#### Scenario: 输出 V1 最小诊断字段

- **WHEN** profile 完成模式决策
- **THEN** 系统 SHALL 输出包含 `mode/source/reason/markers` 的摘要信息

#### Scenario: markers 输出命中变量

- **WHEN** 自动降级或显式配置命中环境变量
- **THEN** 系统 SHALL 在 `markers` 中列出全部命中的变量名

### Requirement: z 函数懒加载

当 zoxide 已安装但因 `SkipTools`/`SkipZoxide` 未在初始化阶段加载时，SHALL 创建一个全局 `z` 函数作为懒加载代理，首次调用时自动初始化 zoxide 并替换自身。

#### Scenario: 懒加载触发

- **WHEN** zoxide 已安装但未在初始化阶段加载，用户首次调用 `z` 命令
- **THEN** SHALL 加载 zoxide 初始化脚本、移除懒加载代理函数、执行实际的 `z` 命令

### Requirement: PowerShell 5.1 兼容性

脚本 SHALL 在顶部检测 `$IsWindows` 是否已定义。若未定义（PowerShell 5.1 环境），SHALL 设置 `$IsWindows = $true`、`$IsLinux = $false`、`$IsMacOS = $false`。

#### Scenario: PowerShell 5.1 环境

- **WHEN** 在 Windows PowerShell 5.1 中加载脚本
- **THEN** `$IsWindows` SHALL 为 `$true`，所有平台条件分支 SHALL 正确执行 Windows 路径
