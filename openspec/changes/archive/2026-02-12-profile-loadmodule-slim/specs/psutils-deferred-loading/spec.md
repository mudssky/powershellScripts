## MODIFIED Requirements

### Requirement: psutils 分层延迟加载

Profile 启动时 SHALL 仅同步加载 psutils 的核心子模块集合。核心模块列表按平台差异化：
- 全平台：`os.psm1`、`cache.psm1`、`proxy.psm1`、`wrapper.psm1`
- 仅 Linux/macOS：`env.psm1`（`Sync-PathFromBash` 依赖）

`test.psm1` SHALL NOT 在同步路径加载（已被 `Get-Command` 批量检测替代）。

其余子模块 SHALL 通过 OnIdle 异步机制延迟加载。

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

### Requirement: 延迟加载防护栏 — 静态 Pester 测试

SHALL 存在 Pester 测试扫描 profile 同步路径文件中的 `Get-Command -Name` 调用，验证引用的函数名属于核心模块导出函数集合。核心模块集合 SHALL 反映平台条件化后的最小集（`os`、`cache`、`proxy`、`wrapper`），`test` 和 `env` 的函数 SHALL NOT 出现在同步路径的 `Get-Command` 调用中。

#### Scenario: 同步路径中 Get-Command 引用的函数属于核心模块

- **WHEN** Pester 测试扫描到 `Get-Command -Name <函数名>` 调用
- **THEN** `<函数名>` SHALL 存在于核心子模块（`os`、`cache`、`proxy`、`wrapper`）的导出函数中，否则测试 SHALL 失败
