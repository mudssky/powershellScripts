## ADDED Requirements

### Requirement: psutils 分层延迟加载

Profile 启动时 SHALL 仅同步加载 psutils 的核心子模块集合。核心模块列表按平台差异化：
- 全平台：`os.psm1`、`cache.psm1`、`proxy.psm1`、`wrapper.psm1`
- 仅 Linux/macOS：`env.psm1`（`Sync-PathFromBash` 依赖）

`test.psm1` SHALL NOT 在同步路径加载（已被 `Get-Command` 批量检测替代）。

其余子模块 SHALL 通过异步机制延迟加载。

#### Scenario: 同步阶段仅加载核心子模块

- **WHEN** profile 以 Full 或 Minimal 模式在 Windows 上启动并进入 core-loaders 阶段
- **THEN** SHALL 仅加载 4 个核心子模块（`os`、`cache`、`proxy`、`wrapper`），不加载 `test` 和 `env`

#### Scenario: Linux/macOS 同步阶段额外加载 env 模块

- **WHEN** profile 以 Full 或 Minimal 模式在 Linux 或 macOS 上启动并进入 core-loaders 阶段
- **THEN** SHALL 加载 5 个核心子模块（`os`、`cache`、`env`、`proxy`、`wrapper`）

#### Scenario: 核心函数在启动后立即可用

- **WHEN** profile 启动完成（prompt 已显示）
- **THEN** 以下函数 SHALL 立即可调用：`Invoke-WithCache`、`Invoke-WithFileCache`、`Get-CacheStats`、`Clear-ExpiredCache`、`Set-Proxy`、`Close-Proxy`、`Start-Proxy`、`Get-OperatingSystem`、`Test-Administrator`、`Set-CustomAlias`、`Get-CustomAlias`
- **THEN** 在 Linux/macOS 上额外可调用：`Sync-PathFromBash`、`Get-Dotenv`、`Import-EnvPath`、`Set-EnvPath`、`Add-EnvPath`、`Remove-FromEnvPath`

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

同步阶段的加载 SHALL 遵循依赖顺序：`os.psm1` 必须在 `cache.psm1` 之前加载。

#### Scenario: Windows 依赖顺序正确

- **WHEN** profile 同步阶段在 Windows 上加载核心子模块
- **THEN** SHALL 按以下顺序加载：`os` → `cache` → `proxy` → `wrapper`

#### Scenario: Linux/macOS 依赖顺序正确

- **WHEN** profile 同步阶段在 Linux/macOS 上加载核心子模块
- **THEN** SHALL 按以下顺序加载：`os` → `cache` → `env` → `proxy` → `wrapper`

#### Scenario: 子模块加载失败时终止启动

- **WHEN** 任一核心子模块加载失败
- **THEN** SHALL 抛出错误并终止 profile 加载

### Requirement: 同步路径禁止触发 PSModulePath 自动导入

Profile 启动的同步路径（core-loaders 和 initialize-environment 阶段）中 SHALL NOT 存在任何会触发 PSModulePath 自动发现并导入 psutils 全量模块的操作。

#### Scenario: 同步路径中的 Get-Command 不引用非核心模块函数

- **WHEN** 同步路径中存在 `Get-Command -Name <函数名>` 调用
- **THEN** 该函数名 SHALL 属于核心子模块导出的函数，或者该检测 SHALL 被移至 OnIdle 延迟执行

#### Scenario: fzf 键绑定注册延迟到 OnIdle

- **WHEN** profile 启动并执行 `Set-ProfileUtf8Encoding`
- **THEN** SHALL NOT 调用 `Get-Command -Name Register-FzfHistorySmartKeyBinding`（该函数属于 `functions.psm1`，非核心模块）
- **THEN** fzf 键绑定注册 SHALL 在 OnIdle 事件中执行（psutils 全量加载完成后）

### Requirement: OnIdle Action 使用闭包传递变量

OnIdle 事件的 Action 脚本块 SHALL 使用 `.GetNewClosure()` 捕获局部变量，SHALL NOT 使用 `-MessageData` + `$Event.MessageData`（PowerShell 7.5 引擎 bug 导致 `$Event.MessageData` 为 `$null`）。

#### Scenario: 闭包正确捕获模块路径

- **WHEN** OnIdle 事件触发并执行 Action 脚本块
- **THEN** 闭包中的模块路径变量 SHALL 非空，`Import-Module` SHALL 成功执行

### Requirement: 延迟加载防护栏 — 运行时检测

Profile SHALL 在 `Initialize-Environment` 执行后检测 psutils 模块是否被意外全量加载（即延迟加载被短路）。如检测到异常，SHALL 通过 `Write-Warning` 输出提醒。

#### Scenario: 正常情况无警告

- **WHEN** 同步路径未触发 psutils 自动导入，`Initialize-Environment` 执行完毕
- **THEN** SHALL NOT 输出性能守卫警告

#### Scenario: 检测到意外全量加载

- **WHEN** `Initialize-Environment` 执行期间 psutils 模块被意外全量加载（通过 PSModulePath 自动发现）
- **THEN** SHALL 输出 `Write-Warning` 包含 `[性能守卫]` 前缀，提示延迟加载优化失效

#### Scenario: 防护栏仅在诊断模式生效

- **WHEN** `POWERSHELL_PROFILE_TIMING` 未设置或为 `0`
- **THEN** SHALL 跳过运行时检测逻辑，不增加正常启动的开销

### Requirement: 延迟加载防护栏 — 静态 Pester 测试

SHALL 存在 Pester 测试扫描 profile 同步路径文件（`profile/core/*.ps1`、`profile/features/*.ps1`）中的 `Get-Command -Name` 调用，验证引用的函数名属于核心模块导出函数集合。核心模块集合 SHALL 反映平台条件化后的最小集（`os`、`cache`、`proxy`、`wrapper`），`test` 和 `env` 的函数 SHALL NOT 出现在同步路径的 `Get-Command` 调用中。

#### Scenario: 同步路径中 Get-Command 引用的函数属于核心模块

- **WHEN** Pester 测试扫描到 `Get-Command -Name <函数名>` 调用
- **THEN** `<函数名>` SHALL 存在于核心子模块（`os`、`cache`、`proxy`、`wrapper`）的导出函数中，否则测试 SHALL 失败

#### Scenario: 新增 Get-Command 引用非核心函数时 CI 拦截

- **WHEN** 开发者在 profile 同步路径文件中新增了 `Get-Command -Name <非核心函数>` 调用
- **THEN** CI 中的 Pester 测试 SHALL 失败并提示该函数会触发 psutils 全量自动导入
