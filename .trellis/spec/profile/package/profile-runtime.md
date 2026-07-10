# Profile Runtime Contract

## Scenario: Unified Profile Runtime

### 1. Scope / Trigger

- Trigger：修改 `profile/profile.ps1`、`profile/core/**`、`profile/features/environment.ps1`、Profile 性能诊断或相关 Pester 测试。
- Scope：统一入口、平台策略、模式加载计划、核心模块同步加载、OnIdle 生命周期、失败降级与计时报告。
- Design intent：共享执行机制，集中平台差异；测量真实入口，避免实现与诊断各维护一套逻辑。

### 2. Signatures

- 平台上下文：
  - `Get-ProfilePlatformContext [-Platform Auto|Windows|MacOS|Linux]`
- 最小初始化：
  - `Initialize-ProfileBootstrap -ProfileRoot <string> [-PlatformContext <PSCustomObject>]`
- 核心加载：
  - `Import-ProfileCoreModules -ProfileRoot <string> -PlatformContext <PSCustomObject>`
  - `Register-ProfileOnIdle -ProfileRoot <string> -ModuleManifest <string>`
  - `Invoke-ProfileCoreLoaders -ProfileRoot <string> -Mode Full|Minimal -PlatformContext <PSCustomObject>`
- 真实入口诊断：
  - `profile.ps1 [-SkipTools] [-SkipProxy] [-SkipStarship] [-SkipZoxide] [-SkipAliases] [-TimingOutputPath <path>]`
  - `Debug-ProfilePerformance.ps1 [-Mode Full|Minimal|UltraMinimal] [-Iterations <1..100>] [-AsJson] [-OutputPath <path>]`

### 3. Contracts

#### PlatformContext

`Get-ProfilePlatformContext` 返回对象至少包含：

- `Id`: `windows`、`macos` 或 `linux`
- `IsWindows`: bool
- `IsUnix`: bool
- `CoreModules`: string[]
- `PackageManagers`: string[]
- `SyncBashPath`: bool
- `CacheId`: `win`、`macos` 或 `linux`
- `PathVariableName`: `Path` 或 `PATH`
- `PathComparer`: Windows 不区分大小写，Unix 区分大小写

同步模块集合：

- Windows：`os`、`cache`、`commandDiscovery`、`proxy`、`wrapper`
- macOS/Linux：Windows 集合加 `env`

#### Mode behavior

- Full：同步核心模块、用户别名、工具探测、工具初始化、安装提示和别名注册。
- Minimal：同步核心模块保持立即可用；不读取用户别名配置，不执行工具/包管理器探测、工具初始化或安装提示。
- UltraMinimal：不加载 psutils、loaders 或完整 Environment；保留 UTF-8、`POWERSHELL_SCRIPTS_ROOT`、仓库 `bin` PATH，以及 `Show-MyProfileHelp`、`Initialize-Environment`、`Set-PowerShellProfile` 公共函数。

#### OnIdle state

- Profile 使用 `$Global:__PowerShellProfileOnIdleState` 标识当前会话已注册延迟任务。
- 同一会话重复加载 Profile 时不得创建第二个 Profile OnIdle 订阅。
- OnIdle 内的 psutils、wrapper、fzf、PSReadLine 步骤分别隔离错误。
- 稳定路径通过 `[scriptblock]::Create()` 内联，不使用 `.GetNewClosure()` 或 `-MessageData`。

#### Timing report

`-TimingOutputPath` JSON 至少包含：

- `Platform`、`PowerShellVersion`
- `RequestedMode`、`FinalMode`、`ModeSource`、`ModeReason`
- `Fallback`
- `Timings`
- `ProfileInternalMs`

诊断汇总额外包含：

- `Iterations`
- `ProfileInternal`: average/median/min/max/samples
- `ProcessElapsed`: average/median/min/max/samples
- `Phases`
- `Notes`

### 4. Validation & Error Matrix

| Condition | Expected behavior |
|---|---|
| 无法加载 encoding/bootstrap/mode/platform 或无法判定模式/平台 | 明确报错并终止本次 Profile 初始化 |
| 必需 runtime definition、核心模块或完整环境初始化失败 | 输出 `[ProfileFallback]`，包含组件和原始错误，最终降级到 UltraMinimal |
| 用户别名配置失败 | 告警，使用空别名集合继续 Full |
| Help/Install 定义失败 | 告警，基础 Profile 继续 |
| OnIdle 单项失败 | 告警并继续其他延迟任务，不影响同步核心函数 |
| Minimal 启动 | `Find-ExecutableCommand` 不得执行，核心命令仍立即可用 |
| 重复加载 Profile | Profile OnIdle 订阅最多一个 |
| 性能诊断请求模式与最终模式不一致 | 诊断样本失败，禁止把 fallback 数字计入目标模式 |

### 5. Good / Base / Bad Cases

- Good：平台判断只在 `Get-ProfilePlatformContext` 构造，environment/loaders 消费上下文字段。
- Good：`Debug-ProfilePerformance.ps1` 启动新进程执行真实入口，再汇总 JSON。
- Base：Full 模式仍允许通过 Skip 参数隔离某个工具，但不能改变模式本身。
- Bad：重新创建 `profile_windows.ps1` 与 `profile_unix.ps1` 两套完整逻辑。
- Bad：为“详细计时”复制 `Initialize-Environment`、模块列表或平台分支。
- Bad：用 `SkipTools -and SkipAliases` 推断 Minimal；Full 用户可能显式同时传入两个开关。
- Bad：把单机绝对毫秒门槛写进 CI。

### 6. Tests Required

- `ProfileMode.Tests.ps1`
  - 模式优先级、UltraMinimal bootstrap、仓库 PATH 幂等。
- `ProfileInstallHints.Tests.ps1`
  - Full 批量命令探测。
  - Minimal 对 `Find-ExecutableCommand` 断言 `Times 0`。
- `ProfileLoading.Tests.ps1`
  - Windows/macOS/Linux PlatformContext 矩阵。
  - UltraMinimal 公共函数存在且 psutils 模块数为 0。
  - Minimal 核心命令存在、别名配置为空、OnIdle 为 1。
  - 重复加载后 OnIdle 仍为 1。
  - 缺失核心模块时输出可见 fallback 并进入 UltraMinimal。
  - `-AsJson` 诊断报告样本数、阶段与模式正确。
- `DeferredLoading.Tests.ps1`
  - 同步路径禁止引用非核心 psutils 函数。
  - OnIdle 使用稳定字面量路径且禁止 `.GetNewClosure()`。
- 运行态验证：macOS 宿主与 Linux Docker 都运行 Profile 窄测；Windows 由平台矩阵和 CI 覆盖。

### 7. Wrong vs Correct

#### Wrong

```powershell
# 诊断脚本复制一份模块加载与工具初始化，最终必然漂移。
. ./core/loadModule.ps1
$availableTools = Find-ExecutableCommand -Name @('starship', 'zoxide')
```

#### Correct

```powershell
# 真实入口写出结构化计时，诊断器只负责新进程采样与统计。
pwsh -NoProfile -NoLogo -File ./profile/profile.ps1 `
    -TimingOutputPath $timingPath
```

理由：模式分流、平台策略、失败降级和计时都只有一个事实来源，测试与性能报告观察的是用户真正执行的代码路径。
