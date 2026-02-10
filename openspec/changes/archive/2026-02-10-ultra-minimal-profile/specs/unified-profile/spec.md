## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: 统一工具初始化
`Initialize-Environment` 函数 SHALL 维护统一的工具初始化表，包含所有平台工具，并在执行时依据当前模式控制初始化范围。

#### Scenario: Full 模式初始化完整工具链
- **WHEN** 当前模式为 Full 且工具已安装
- **THEN** 系统 SHALL 执行 starship、zoxide、fnm、sccache 等初始化逻辑，并按平台规则完成配置

#### Scenario: Minimal 模式跳过交互增强
- **WHEN** 当前模式为 Minimal
- **THEN** 系统 SHALL 跳过交互增强与别名注册，但仍保留模块函数可用性

#### Scenario: UltraMinimal 模式仅保留最小能力
- **WHEN** 当前模式为 UltraMinimal
- **THEN** 系统 SHALL 跳过模块加载、工具初始化、代理检测、PATH 同步、别名与包装函数注册，仅保留 UTF8 设置、`POWERSHELL_SCRIPTS_ROOT` 以及基础变量兼容

### Requirement: 统一 Show-MyProfileHelp
`Show-MyProfileHelp` 函数 SHALL 在 Full 与 Minimal 模式下显示完整帮助信息，并在 UltraMinimal 模式下提供可降级的提示输出。

#### Scenario: Full 或 Minimal 模式显示完整帮助
- **WHEN** 当前模式为 Full 或 Minimal 且用户执行 `Show-MyProfileHelp`
- **THEN** 系统 SHALL 显示完整帮助段落与关键函数说明

#### Scenario: UltraMinimal 模式降级帮助输出
- **WHEN** 当前模式为 UltraMinimal 且用户执行 `Show-MyProfileHelp`
- **THEN** 系统 SHALL 输出模式与最小能力提示，且不因未加载模块而报错
