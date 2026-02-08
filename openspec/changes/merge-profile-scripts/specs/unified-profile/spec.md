## ADDED Requirements

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
`Show-MyProfileHelp` 函数 SHALL 显示以下所有信息段：自定义别名、自定义函数别名、自定义函数包装、核心管理函数、关键环境变量、用户级持久环境变量。

#### Scenario: 调用帮助函数
- **WHEN** 用户执行 `Show-MyProfileHelp`
- **THEN** SHALL 依次显示所有 6 个信息段，每段带有彩色标题

### Requirement: 统一工具初始化
`Initialize-Environment` 函数 SHALL 维护统一的工具初始化表，包含所有平台的工具。每个工具的初始化逻辑 SHALL 内部判断平台适用性。

#### Scenario: 通用工具初始化
- **WHEN** starship 或 zoxide 已安装
- **THEN** SHALL 在所有平台上初始化该工具，使用 `Invoke-WithFileCache` 缓存初始化脚本

#### Scenario: 平台特定工具初始化
- **WHEN** 在 Windows 平台且 sccache 已安装
- **THEN** SHALL 设置 `$env:RUSTC_WRAPPER = 'sccache'`
- **WHEN** 在 Unix 平台且 fnm 已安装
- **THEN** SHALL 执行 `fnm env --use-on-cd | Out-String | Invoke-Expression`

#### Scenario: Minimal 模式
- **WHEN** 指定 `-Minimal` 参数或存在 `minimal` 标记文件或设置了 `$env:POWERSHELL_PROFILE_MINIMAL`
- **THEN** SHALL 跳过工具初始化和别名设置

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
