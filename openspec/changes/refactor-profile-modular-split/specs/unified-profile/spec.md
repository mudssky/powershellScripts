## ADDED Requirements

### Requirement: 模块化入口编排
`profile.ps1` 在完成拆分后 SHALL 继续作为唯一统一入口，并以可维护的模块化方式组织内部实现。

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
