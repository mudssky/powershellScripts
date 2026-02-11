## ADDED Requirements

### Requirement: psutils 分层延迟加载

Profile 启动时 SHALL 仅同步 dot-source psutils 的核心子模块集合（`os.psm1`、`cache.psm1`、`test.psm1`、`env.psm1`、`proxy.psm1`、`wrapper.psm1`），不执行 `Import-Module psutils.psd1`。其余子模块 SHALL 通过异步机制延迟加载。

#### Scenario: 同步阶段仅加载核心子模块

- **WHEN** profile 以 Full 或 Minimal 模式启动并进入 core-loaders 阶段
- **THEN** SHALL 仅 dot-source 6 个核心子模块（`os`、`cache`、`test`、`env`、`proxy`、`wrapper`），不加载其余 14 个子模块

#### Scenario: 核心函数在启动后立即可用

- **WHEN** profile 启动完成（prompt 已显示）
- **THEN** 以下函数 SHALL 立即可调用：`Invoke-WithCache`、`Invoke-WithFileCache`、`Get-CacheStats`、`Clear-ExpiredCache`、`Set-Proxy`、`Close-Proxy`、`Start-Proxy`、`Sync-PathFromBash`、`Get-Dotenv`、`Import-EnvPath`、`Set-EnvPath`、`Add-EnvPath`、`Remove-FromEnvPath`、`Get-OperatingSystem`、`Test-Administrator`、`Test-EXEProgram`、`Test-ApplicationInstalled`、`Set-CustomAlias`、`Get-CustomAlias`

### Requirement: OnIdle 异步全量加载

Profile 启动后 SHALL 注册 `PowerShell.OnIdle` 引擎事件（`-MaxTriggerCount 1`），在用户首次空闲时执行 `Import-Module psutils.psd1 -Force -Global` 加载完整模块。

#### Scenario: 空闲时静默加载完整模块

- **WHEN** 用户在 prompt 显示后首次空闲（OnIdle 事件触发）
- **THEN** SHALL 执行完整 psutils 模块导入，覆盖同步阶段 dot-source 的函数，所有 70+ 个函数 SHALL 可用于 Tab 补全和直接调用

#### Scenario: OnIdle 仅触发一次

- **WHEN** OnIdle 事件已触发并完成全量加载
- **THEN** SHALL 不再触发后续 OnIdle 加载（通过 `-MaxTriggerCount 1` 保证）

#### Scenario: OnIdle 加载失败不影响已有函数

- **WHEN** OnIdle 事件中的 `Import-Module` 执行失败
- **THEN** 同步阶段已加载的核心函数 SHALL 继续正常工作，错误 SHALL 通过 `Write-Warning` 静默记录

### Requirement: PSModulePath 兜底发现

`loadModule.ps1` SHALL 将 psutils 模块目录追加到 `$env:PSModulePath`（如尚未存在），确保 PowerShell 自动加载机制可以发现 `psutils.psd1`。

#### Scenario: 未加载函数首次调用触发自动加载

- **WHEN** 用户在 OnIdle 触发前调用了一个非核心子模块的函数（如 `Get-Tree`）
- **THEN** PowerShell 的自动模块加载机制 SHALL 通过 `PSModulePath` 发现 `psutils.psd1` 并执行 `Import-Module`，函数 SHALL 成功执行

#### Scenario: PSModulePath 不重复追加

- **WHEN** psutils 模块目录已存在于 `$env:PSModulePath` 中
- **THEN** SHALL 不重复追加，保持 PSModulePath 干净

### Requirement: 核心子模块 dot-source 加载顺序

同步阶段的 dot-source SHALL 遵循依赖顺序：`os.psm1` 必须在 `cache.psm1` 之前加载（`cache.psm1` 的模块级代码依赖 `Get-OperatingSystem`）。

#### Scenario: 依赖顺序正确

- **WHEN** profile 同步阶段加载核心子模块
- **THEN** SHALL 按以下顺序 dot-source：`os` → `cache` → `test` → `env` → `proxy` → `wrapper`

#### Scenario: 子模块加载失败时终止启动

- **WHEN** 任一核心子模块 dot-source 失败
- **THEN** SHALL 抛出错误并终止 profile 加载（与当前 `Import-Module -ErrorAction Stop` 行为一致）
