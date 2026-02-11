## Why

上一轮 Profile 加载优化（`profile-loading-optimization`）将加载时间从约 2s 降至约 1.77s，解决了 starship 缓存、Tab 补全、代理探测等问题。但当前 Full 模式仍需 ~1.77s，其中 `core-loaders` 阶段（680ms）因 psutils 全量加载 19 个子模块成为最大瓶颈，`initialize-environment` 阶段（822ms）中 fnm 每次启动外部进程、环境变量检测使用低效 Provider API 等问题也有显著优化空间。需要通过延迟加载、缓存和 API 替换将 Full 模式加载时间降至 ~1.1s 以下。

## What Changes

- 将 psutils 模块从全量同步加载改为**分层延迟加载**：启动时仅 dot-source 5-6 个 profile 必需子模块，其余 14 个子模块通过 `Register-EngineEvent PowerShell.OnIdle` 在空闲时静默加载，并以 `PSModulePath` 自动发现机制兜底
- 将 `fnm env --use-on-cd` 初始化改为 `Invoke-WithFileCache` 缓存模式，与 starship/zoxide 的缓存策略保持一致
- 将 `Get-ProfileModeDecision` 中的环境变量检测从 `Get-Item -Path "Env:$Name"`（PowerShell Provider）替换为 `[System.Environment]::GetEnvironmentVariable()`（.NET 原生调用）
- 将 `wrapper.ps1` 加载改为延迟加载，在 OnIdle 或首次调用时才 dot-source
- **修复 `Set-ProfileUtf8Encoding` 中 `Get-Command Register-FzfHistorySmartKeyBinding` 触发 psutils 全量自动导入的问题**：该函数定义在 `functions.psm1`（非核心模块），`Get-Command` 通过 PSModulePath 自动发现导致全量模块加载，完全抵消延迟加载收益（+1200ms）。将 fzf 键绑定注册移至 OnIdle 延迟执行
- **修复 OnIdle 事件中 `-MessageData` 在 PowerShell 7.5 下为 `$null` 的引擎 bug**：改用 `.GetNewClosure()` 通过闭包捕获变量
- **新增延迟加载防护栏（静态 + 运行时双层检测）**：Pester 测试扫描 profile 同步路径中的函数引用，验证不触发 PSModulePath 自动导入；profile 运行时在 `Initialize-Environment` 执行后检测 psutils 是否被意外全量加载，如是则输出 Warning 提醒开发者

## Capabilities

### New Capabilities

- `psutils-deferred-loading`: psutils 模块分层延迟加载能力，将 19 个子模块拆为同步核心集与异步延迟集，通过 OnIdle 事件和 PSModulePath 自动发现实现无感全量加载

### Modified Capabilities

- `unified-profile`: 修改模块加载流程（分层延迟）、环境变量检测 API、fnm 初始化缓存、wrapper 延迟加载

## Impact

- **profile/core/loadModule.ps1**: 核心改造 — 从 `Import-Module psutils.psd1` 改为 dot-source 核心子模块 + OnIdle 延迟全量加载 + PSModulePath 兜底；OnIdle Action 使用 `.GetNewClosure()` 替代 `-MessageData`（规避 PowerShell 7.5 引擎 bug）
- **profile/core/mode.ps1**: `Test-EnvSwitchEnabled` / `Test-EnvValuePresent` 函数 API 替换
- **profile/core/encoding.ps1**: 将 `Register-FzfHistorySmartKeyBinding` 调用从同步执行移至 OnIdle 延迟执行，避免 `Get-Command` 触发 psutils 全量自动导入
- **profile/profile.ps1**: 新增运行时防护栏 — 在 `Initialize-Environment` 执行后检测 psutils 是否被意外全量加载
- **tests/**: 新增 Pester 测试 — 静态扫描 profile 同步路径文件中的函数引用，与核心模块导出列表交叉验证
- **profile/features/environment.ps1**: fnm 初始化改用 `Invoke-WithFileCache` 缓存、wrapper.ps1 延迟加载
- **profile/core/loaders.ps1**: 调整 `$InvokeProfileCoreLoaders` 脚本块中的加载顺序和方式
- **psutils/modules/**: 子模块本身不改动，仅改变加载时机
