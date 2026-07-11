## MODIFIED Requirements

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
- **THEN** SHALL 使用 `Invoke-WithFileCache` 缓存 `fnm env --use-on-cd` 输出并 dot-source 缓存文件，而非每次启动外部进程

#### Scenario: Minimal 模式跳过交互增强

- **WHEN** 当前模式为 Minimal
- **THEN** SHALL 跳过工具初始化和别名注册，但保留模块函数可用性

#### Scenario: UltraMinimal 模式仅保留最小能力

- **WHEN** 当前模式为 UltraMinimal
- **THEN** SHALL 跳过模块加载、工具初始化、代理检测、PATH 同步、别名与包装函数注册，仅保留 UTF8 设置、`POWERSHELL_SCRIPTS_ROOT` 与基础变量兼容

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

### Requirement: 模块化入口编排

`profile.ps1` 在完成拆分后 SHALL 继续作为统一入口，并以可维护的模块化方式组织内部实现。core-loaders 阶段 SHALL 使用分层延迟加载策略加载 psutils 模块。

#### Scenario: 入口路径保持不变

- **WHEN** 用户执行 `./profile/profile.ps1`
- **THEN** 系统 SHALL 通过统一入口完成初始化，且不要求用户修改现有调用方式

#### Scenario: wrapper.ps1 延迟加载

- **WHEN** profile 进入 core-loaders 阶段
- **THEN** `wrapper.ps1` 的 dot-source SHALL 被纳入 OnIdle 延迟加载，不在同步阶段执行
