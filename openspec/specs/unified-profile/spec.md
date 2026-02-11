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

`Initialize-Environment` 函数 SHALL 维护统一的工具初始化表，并依据当前模式控制初始化范围。每个工具的初始化逻辑 SHALL 内部判断平台适用性。工具检测 SHALL 使用批量 `Get-Command` 查询替代逐个调用 `Test-EXEProgram`，以减少 PATH 扫描次数。

#### Scenario: Full 模式初始化完整工具链

- **WHEN** 当前模式为 Full 且工具已安装
- **THEN** SHALL 执行 starship、zoxide、fnm、sccache 等初始化逻辑，并按平台规则完成配置

#### Scenario: 批量工具检测

- **WHEN** 进入工具初始化阶段
- **THEN** SHALL 使用单次 `Get-Command -Name @(...) -CommandType Application` 批量检测所有工具的可用性，而非对每个工具独立调用 `Test-EXEProgram`

#### Scenario: 通用工具初始化

- **WHEN** starship 或 zoxide 已安装
- **THEN** SHALL 在所有平台上初始化该工具，使用 `Invoke-WithFileCache` 缓存初始化脚本

#### Scenario: starship 缓存完整初始化脚本

- **WHEN** 使用 `Invoke-WithFileCache` 缓存 starship 初始化脚本
- **THEN** Generator SHALL 使用 `& starship init powershell --print-full-init` 以缓存完整的初始化脚本（约 200 行），而非缓存引导代码

#### Scenario: 平台特定工具初始化

- **WHEN** 在 Windows 平台且 sccache 已安装
- **THEN** SHALL 设置 `$env:RUSTC_WRAPPER = 'sccache'`
- **WHEN** 在 Unix 平台且 fnm 已安装
- **THEN** SHALL 使用临时文件 dot-source 方式执行 `fnm env --use-on-cd` 初始化（fnm env 输出包含会话特定 multishell 临时路径，不适合长期缓存）

#### Scenario: Minimal 模式跳过交互增强

- **WHEN** 当前模式为 Minimal
- **THEN** SHALL 跳过工具初始化和别名注册，但保留模块函数可用性

#### Scenario: UltraMinimal 模式仅保留最小能力

- **WHEN** 当前模式为 UltraMinimal
- **THEN** SHALL 跳过模块加载、工具初始化、代理检测、PATH 同步、别名与包装函数注册，仅保留 UTF8 设置、`POWERSHELL_SCRIPTS_ROOT` 与基础变量兼容

### Requirement: 模块化入口编排

`profile.ps1` 在完成拆分后 SHALL 继续作为统一入口，并以可维护的模块化方式组织内部实现。core-loaders 阶段 SHALL 使用分层延迟加载策略加载 psutils 模块。

#### Scenario: 入口路径保持不变

- **WHEN** 用户执行 `./profile/profile.ps1`
- **THEN** 系统 SHALL 通过统一入口完成初始化，且不要求用户修改现有调用方式

#### Scenario: wrapper.ps1 延迟加载

- **WHEN** profile 进入 core-loaders 阶段
- **THEN** `wrapper.ps1` 的 dot-source SHALL 被纳入 OnIdle 延迟加载，不在同步阶段执行

### Requirement: 模块加载顺序可控

拆分后的实现 SHALL 采用确定性的 dot-source 顺序加载核心模块、配置加载器与功能模块，以避免函数未定义和作用域初始化错误。

#### Scenario: 核心模块先于功能模块

- **WHEN** profile 启动并开始加载内部脚本
- **THEN** 系统 SHALL 先加载模式决策与基础工具模块，再加载依赖这些能力的功能模块

#### Scenario: 配置加载器在功能执行前完成

- **WHEN** profile 进入扩展加载阶段
- **THEN** 系统 SHALL 在别名注册和帮助信息展示前完成配置脚本加载

### Requirement: 模式语义在拆分后保持一致

在模块化拆分后，`Full/Minimal/UltraMinimal` 的模式决策优先级与行为边界 SHALL 与拆分前一致。

#### Scenario: Full 模式优先级保持

- **WHEN** 设置 `POWERSHELL_PROFILE_FULL=1`
- **THEN** 系统 SHALL 强制使用 Full 模式并覆盖其他模式开关

#### Scenario: Minimal 模式手动触发保持

- **WHEN** 设置 `POWERSHELL_PROFILE_MODE=minimal`
- **THEN** 系统 SHALL 进入 Minimal 模式并保持"跳过工具与别名"的语义

#### Scenario: UltraMinimal 自动降级保持

- **WHEN** 命中 `CODEX_THREAD_ID` 或 `CODEX_SANDBOX_NETWORK_DISABLED`
- **THEN** 系统 SHALL 自动进入 UltraMinimal 模式，并保持最小初始化路径

### Requirement: 对外函数兼容可用

拆分后 `Show-MyProfileHelp`、`Initialize-Environment`、`Set-PowerShellProfile` SHALL 继续可用，并保持原有职责。

#### Scenario: 关键函数仍可调用

- **WHEN** profile 加载完成后用户调用关键函数
- **THEN** 系统 SHALL 成功执行函数且不因内部文件拆分而报函数不存在

### Requirement: 模式解析优先级与自动降级

`profile/profile.ps1` SHALL 按固定优先级解析运行模式，优先级为 `POWERSHELL_PROFILE_FULL` > `POWERSHELL_PROFILE_MODE` > `POWERSHELL_PROFILE_ULTRA_MINIMAL` > 自动判定 > 默认值。环境变量检测 SHALL 使用 `[System.Environment]::GetEnvironmentVariable()` .NET 原生 API 而非 `Get-Item -Path "Env:..."` PowerShell Provider。

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

#### Scenario: 环境变量检测性能

- **WHEN** `Get-ProfileModeDecision` 执行环境变量检测
- **THEN** SHALL 使用 `[System.Environment]::GetEnvironmentVariable()` 而非 `Get-Item -Path "Env:..."`，单次检测耗时 SHALL 低于 1ms

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

### Requirement: PowerShell 7+ 运行时基线
`profile.ps1` SHALL 仅支持 PowerShell 7+（`pwsh`）运行时，不提供 PowerShell 5.x 兼容路径。

#### Scenario: 受支持运行时正常加载
- **WHEN** 用户在 PowerShell 7+ 环境执行 `profile.ps1`
- **THEN** 系统 SHALL 继续执行统一入口初始化流程

#### Scenario: 非受支持运行时不受支持
- **WHEN** 用户在 Windows PowerShell 5.1 执行 `profile.ps1`
- **THEN** 系统 SHALL 不保证行为正确且不提供兼容分支

### Requirement: 用户别名配置目录化
用户别名配置 SHALL 从专用配置目录加载，而非直接放置在 `profile/` 根目录。

#### Scenario: 从配置目录加载用户别名
- **WHEN** profile 初始化扩展加载链路
- **THEN** 系统 SHALL 从约定的别名配置目录读取用户别名定义并完成注册

#### Scenario: 根目录不再承载别名配置文件
- **WHEN** 用户查看 `profile/` 根目录结构
- **THEN** 系统 SHALL 不再要求 `user_aliases.ps1` 位于根目录才能完成加载

### Requirement: 代理探测性能优化

`Set-Proxy -Command auto` 的 TCP 探测 SHALL 使用缩短的超时时间，并缓存代理可用性状态以避免每次 profile 加载都做网络探测。

#### Scenario: TCP 超时缩短

- **WHEN** 执行 `Set-Proxy -Command auto`
- **THEN** TCP 连接超时 SHALL 不超过 50ms

#### Scenario: 代理状态缓存

- **WHEN** Profile 加载且代理状态缓存有效（5 分钟内）
- **THEN** SHALL 直接使用缓存的代理状态，不执行 TCP 探测

#### Scenario: 缓存过期重新探测

- **WHEN** Profile 加载且代理状态缓存已过期或不存在
- **THEN** SHALL 执行 TCP 探测并更新缓存

#### Scenario: 手动操作绕过缓存

- **WHEN** 用户显式调用 `Set-Proxy on` 或 `Set-Proxy off`
- **THEN** SHALL 直接执行操作并更新缓存状态

### Requirement: 编码初始化优化

`Set-ProfileUtf8Encoding` SHALL 直接调用 PSReadLine API 而不做 `Get-Command` 可用性检查（PowerShell 7+ 基线保证 PSReadLine 内置），仅对非内置模块（如 PSFzf）的函数用限定类型的 `Get-Command` 检查。

#### Scenario: PSReadLine 直接调用

- **WHEN** 执行 `Set-ProfileUtf8Encoding`
- **THEN** SHALL 直接调用 `Set-PSReadLineKeyHandler` 而不先用 `Get-Command` 检查其是否存在

#### Scenario: fzf 键绑定延迟到 OnIdle

- **WHEN** profile 启动并执行 `Set-ProfileUtf8Encoding`
- **THEN** SHALL NOT 调用 `Get-Command -Name Register-FzfHistorySmartKeyBinding`（该函数属于 `functions.psm1`，非核心模块）
- **THEN** fzf 键绑定注册 SHALL 在 OnIdle 事件中执行（psutils 全量加载完成后）

### Requirement: Tab 补全模式

`Set-ProfileUtf8Encoding` SHALL 将 Tab 键绑定为 `Complete` 模式（补全最长公共前缀，多次 Tab 循环候选），不使用 `MenuComplete` 模式（一次性枚举所有候选）。

#### Scenario: Tab 键使用 Complete 模式

- **WHEN** Profile 加载完成后用户按下 Tab 键
- **THEN** SHALL 使用 `Complete` 函数进行补全，仅补全到最长公共前缀

### Requirement: PSModulePath 精简

`profile/core/loadModule.ps1` SHALL 仅对 `PSModulePath` 执行去重操作，不向其中追加项目父目录等额外路径（psutils 兜底路径除外），以减少命令发现阶段的目录扫描开销。

#### Scenario: 不添加额外模块路径

- **WHEN** Profile 加载模块
- **THEN** SHALL 不将项目父目录追加到 `PSModulePath`（psutils 模块目录的兜底追加除外）

#### Scenario: 保留去重逻辑

- **WHEN** `PSModulePath` 中存在重复路径
- **THEN** SHALL 去除重复条目
