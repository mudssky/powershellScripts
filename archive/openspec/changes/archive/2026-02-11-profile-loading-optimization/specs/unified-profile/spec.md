## MODIFIED Requirements

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
- **THEN** SHALL 执行 `fnm env --use-on-cd | Out-String | Invoke-Expression`

#### Scenario: Minimal 模式跳过交互增强

- **WHEN** 当前模式为 Minimal
- **THEN** SHALL 跳过工具初始化和别名注册，但保留模块函数可用性

#### Scenario: UltraMinimal 模式仅保留最小能力

- **WHEN** 当前模式为 UltraMinimal
- **THEN** SHALL 跳过模块加载、工具初始化、代理检测、PATH 同步、别名与包装函数注册，仅保留 UTF8 设置、`POWERSHELL_SCRIPTS_ROOT` 与基础变量兼容

## ADDED Requirements

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

#### Scenario: PSFzf 限定类型检查

- **WHEN** 检查 `Register-FzfHistorySmartKeyBinding` 可用性
- **THEN** SHALL 使用 `Get-Command -CommandType Function` 限定搜索范围

### Requirement: Tab 补全模式

`Set-ProfileUtf8Encoding` SHALL 将 Tab 键绑定为 `Complete` 模式（补全最长公共前缀，多次 Tab 循环候选），不使用 `MenuComplete` 模式（一次性枚举所有候选）。

#### Scenario: Tab 键使用 Complete 模式

- **WHEN** Profile 加载完成后用户按下 Tab 键
- **THEN** SHALL 使用 `Complete` 函数进行补全，仅补全到最长公共前缀

### Requirement: PSModulePath 精简

`profile/core/loadModule.ps1` SHALL 仅对 `PSModulePath` 执行去重操作，不向其中追加项目父目录等额外路径，以减少命令发现阶段的目录扫描开销。

#### Scenario: 不添加额外模块路径

- **WHEN** Profile 加载模块
- **THEN** SHALL 不将项目父目录追加到 `PSModulePath`

#### Scenario: 保留去重逻辑

- **WHEN** `PSModulePath` 中存在重复路径
- **THEN** SHALL 去除重复条目
