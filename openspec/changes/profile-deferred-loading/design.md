## Context

上一轮优化（`profile-loading-optimization`）已将加载时间从约 2s 降至 ~1.77s。当前各阶段耗时：

| 阶段 | 耗时 | 占比 |
|------|------|------|
| dot-source-definitions | 178ms | 10% |
| mode-decision | 88ms | 5% |
| core-loaders | 680ms | 38% |
| initialize-environment | 822ms | 47% |
| **总计** | **1768ms** | 100% |

`core-loaders` 阶段的 680ms 几乎全部花在 `Import-Module psutils.psd1`（同步加载 19 个 NestedModules），但 profile 启动路径实际只使用其中 5-6 个子模块的约 8 个函数。`initialize-environment` 阶段中 `fnm env --use-on-cd` 每次都启动外部进程（未缓存）、`Get-ProfileModeDecision` 中的 `Get-Item -Path "Env:..."` 使用低效 Provider API 也有显著开销。

已有的延迟加载先例：`environment.ps1` 中 zoxide 的 `z` 函数已使用 stub-and-replace 懒加载模式。

## Goals / Non-Goals

**Goals:**

- 将 Full 模式加载时间从 ~1.77s 降至 ~1.1s 以下
- 用户看到 prompt 后，所有 psutils 函数的 Tab 补全在 1-2 秒内可用
- profile 启动路径中的核心函数（`Invoke-WithCache`、`Set-Proxy`、`Sync-PathFromBash` 等）立即可用
- fnm 初始化与 starship/zoxide 保持一致的缓存策略
- 环境变量检测使用高效 .NET API

**Non-Goals:**

- 不拆分 `psutils.psd1` 为多个独立模块（保持单一模块的发布和维护简单性）
- 不编译为二进制模块（改动量过大，投入产出比低）
- 不修改 psutils 子模块本身的代码逻辑
- 不改变 UltraMinimal / Minimal 模式的行为

## Decisions

### Decision 1: psutils 分层延迟加载策略 — 同步 dot-source 核心子模块 + OnIdle 延迟全量加载 + PSModulePath 兜底

**选择：** 三层组合方案

**方案描述：**

1. **同步阶段（启动时）**：在 `loadModule.ps1` 中不再 `Import-Module psutils.psd1`，改为直接 dot-source 6 个 profile 必需子模块：
   - `os.psm1` — 被 cache.psm1 依赖
   - `cache.psm1` — `Invoke-WithCache`、`Invoke-WithFileCache`
   - `test.psm1` — `Test-EXEProgram`
   - `env.psm1` — `Sync-PathFromBash`
   - `proxy.psm1` — `Set-Proxy`
   - `wrapper.psm1` — `Set-CustomAlias`、`Get-CustomAlias`

2. **异步阶段（空闲时）**：注册 `Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1`，在用户首次空闲时执行 `Import-Module psutils.psd1 -Force -Global`，静默加载完整模块（覆盖 dot-source 的函数，补全其余 14 个子模块的函数）。

3. **兜底阶段（PSModulePath）**：将 psutils 目录追加到 `$env:PSModulePath`，确保即使 OnIdle 未触发，用户调用未加载函数时 PowerShell 仍能自动发现并加载完整模块。

**替代方案：**

- **方案 B：拆分为 psutils-core.psd1 + psutils.psd1**：更干净但需维护两个 manifest，增加长期维护成本。
- **方案 C：仅靠 PSModulePath 自动加载**：不做同步加载，完全按需。但首次调用任一函数都会触发全量加载（19 模块），且 profile 启动路径自身需要核心函数。
- **方案 D：Stub 函数模式**：为每个延迟函数创建 stub，精细但需生成 60+ 个 stub 函数，维护成本高。

**选择 A 的理由：** 不需要改动 psutils.psd1 或子模块本身，仅改动 `loadModule.ps1`。OnIdle 在主 runspace 中执行（非后台 Job），所以函数直接可用于 Tab 补全。dot-source 在后续 `Import-Module -Force` 时会被模块系统正确覆盖，无冲突。

### Decision 2: fnm 初始化改用 Invoke-WithFileCache

**选择：** 与 starship/zoxide 使用相同的 `Invoke-WithFileCache` 模式

**当前实现：**
```powershell
fnm env --use-on-cd | Out-String | Invoke-Expression
```
每次 profile 加载都启动 `fnm` 外部进程（~50-100ms）。

**优化后：**
```powershell
$fnmFile = Invoke-WithFileCache -Key "fnm-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) `
    -Generator { fnm env --use-on-cd } -BaseDir (Join-Path $profileRoot '.cache')
. $fnmFile
```
缓存命中时仅 dot-source 缓存文件，无外部进程开销。

**替代方案：** 无（这是已验证有效的模式，starship/zoxide 已成功使用）。

### Decision 3: 环境变量检测 API 替换

**选择：** 用 `[System.Environment]::GetEnvironmentVariable($Name)` 替换 `Get-Item -Path "Env:$Name"`

**理由：**
- `Get-Item -Path "Env:$Name"` 走 PowerShell Provider 子系统，每次约 ~10ms
- `[Environment]::GetEnvironmentVariable()` 是 .NET 原生调用，约 ~0.1ms
- `Get-ProfileModeDecision` 中调用 `Test-EnvSwitchEnabled` / `Test-EnvValuePresent` 约 8-10 次，累积开销 ~80ms → 优化后 ~1ms

### Decision 4: wrapper.ps1 加载纳入 OnIdle 延迟

**选择：** 将 `wrapper.ps1` 的 dot-source 从同步阶段移到 OnIdle 事件中

**理由：** `wrapper.ps1` 中定义的 `yaz`、`Add-CondaEnv`、`Get-FunctionWrapperInfo` 等函数在 profile 启动路径中不被调用（`Set-AliasProfile` 使用的 `Set-CustomAlias` 来自 `wrapper.psm1` 子模块而非 `wrapper.ps1`）。延迟加载可节省 ~20-30ms。

**注意：** `Set-AliasProfile` 中有对 `$AliasDescPrefix` 变量的引用，如果这个变量依赖 `wrapper.ps1` 中的某些定义，需要确认。经检查，`$AliasDescPrefix` 来自 `wrapper.psm1` 模块级变量 `$Global:DefaultAliasDespPrefix`，该模块已在同步阶段 dot-source，所以安全。

## Risks / Trade-offs

### [风险] PowerShell.OnIdle 事件兼容性不稳定
→ **缓解：** PSModulePath 兜底机制确保即使 OnIdle 永远不触发，用户首次调用未加载函数时 PowerShell 自动发现并加载完整模块。行为等价于"首次使用时延迟加载"。

### [风险] dot-source 的函数在 global scope 而非 module scope
→ **缓解：** OnIdle 的 `Import-Module -Force -Global` 会用模块系统重新注册同名函数，覆盖 dot-source 版本。在覆盖前的短暂窗口期内，函数功能完全一致（代码相同），仅作用域不同。对 profile 场景无实际影响。

### [风险] OnIdle 触发前用户调用了未加载的扩展函数（如 Get-Tree）
→ **缓解：** PSModulePath 自动加载兜底。PowerShell 发现 `psutils.psd1` 的 `FunctionsToExport` 包含该函数名，自动执行 `Import-Module`。用户感知到的是首次调用稍慢（~400ms），后续正常。

### [风险] fnm 缓存文件过期导致环境变量不正确
→ **缓解：** 缓存有效期设为 7 天（与 starship/zoxide 一致）。`fnm env` 输出中的路径是固定的（基于 fnm 安装位置），不会频繁变化。用户手动更新 fnm 版本后，可通过删除 `.cache/fnm-init-powershell*` 强制刷新。

### [权衡] Tab 补全延迟窗口
OnIdle 触发前（通常 prompt 显示后 1-2 秒），非核心子模块的函数 Tab 补全不可用。但 PSModulePath 兜底确保输入完整命令名后可执行。实际影响极小——用户打开 shell 后通常有 1-2 秒的"看一眼 prompt"时间，足够 OnIdle 完成加载。
