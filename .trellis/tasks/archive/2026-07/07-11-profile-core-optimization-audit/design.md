# Profile Core 优化设计

## Design Summary

保留单一 `profile.ps1` 入口，将当前“散落条件分支”收敛为“共享执行机制 + 平台上下文 + 模式加载计划”。启动链先完成 bootstrap 和模式判定，再按模式加载完整定义；UltraMinimal 在进入 feature 层之前返回。

本任务不拆成多个 Trellis 子任务。诊断可信度、加载顺序和模式行为共享同一调用链，必须按一个顺序实施和验证。

## Target Flow

```text
profile.ps1
  ├─ dot-source core/encoding.ps1
  ├─ dot-source core/bootstrap.ps1
  ├─ dot-source core/mode.ps1
  ├─ dot-source core/platform.ps1
  ├─ dot-source features/help.ps1 + features/install.ps1
  ├─ Get-ProfileModeDecision
  ├─ Get-ProfilePlatformContext
  │
  ├─ UltraMinimal
  │    └─ Initialize-ProfileBootstrap -> timing/report -> return
  │
  └─ Full / Minimal
       ├─ dot-source core/loadModule.ps1 + core/loaders.ps1
       ├─ dot-source required features/environment.ps1
       ├─ Invoke-ProfileCoreLoaders -Mode -PlatformContext
       └─ Initialize-Environment -Mode -PlatformContext
```

## Module Boundaries

### `core/bootstrap.ps1`

- 从 `features/environment.ps1` 移入 `Add-ProfileRepositoryBinPath`。
- 新增 `Initialize-ProfileBootstrap`，只设置 `POWERSHELL_SCRIPTS_ROOT`、仓库 `bin` PATH 和 UTF-8。
- 提供轻量 `Initialize-Environment` 兼容包装；UltraMinimal 调用时只执行 bootstrap，Full/Minimal 加载 feature 实现后由完整函数覆盖。
- 函数必须幂等，可被 UltraMinimal 直接调用，也可作为 Full/Minimal 的公共前置步骤。
- 不依赖 psutils 或 feature 层函数。

### `core/platform.ps1`

- 新增纯函数 `Get-ProfilePlatformContext`。
- 默认从 PowerShell 7 的 `$IsWindows/$IsMacOS/$IsLinux` 识别平台；测试可显式传入平台标识。
- 返回稳定对象，至少包含：
  - `Id`: `windows` / `macos` / `linux`
  - `IsWindows`、`IsUnix`
  - `CoreModules`
  - `PackageManagers`
  - `SyncBashPath`
  - `CacheId`
  - `PathComparer`
- Windows 与 Unix 的核心模块差异保留；Linux 专属 Bash PATH 同步通过 capability 表达，不复制 Unix 执行链。

### `core/loadModule.ps1`

- 将当前顶层执行逻辑拆为有文档的导入与 OnIdle 注册函数，输入平台上下文。
- 核心模块导入失败时抛出包含模块名的明确错误，由主入口决定降级。
- PSModulePath 去重继续使用平台上下文中的比较规则。
- OnIdle 使用 Profile 专属的全局状态或订阅 ID 判断待执行、完成和失败状态，重复加载不得并行注册第二个任务。
- OnIdle 内部各任务继续独立 `try/catch`，失败不影响其他延迟任务。

### `core/loaders.ps1`

- 用 `Invoke-ProfileCoreLoaders` 函数替代 `$script:InvokeProfileCoreLoaders` 脚本块。
- Full 与 Minimal 都同步加载现有核心模块。
- 仅 Full 读取用户别名配置；读取失败时告警并使用空集合继续。
- 返回结构化结果，供主入口记录实际模式、加载状态与降级原因。

### `features/environment.ps1`

- 接收模式和平台上下文，停止自行重复推导平台。
- Full 保持现有代理、env、编码、工具探测、工具初始化、缺失提示和别名行为。
- Minimal 完成公共环境、Linux PATH 同步、代理、env 与编码后立即返回，不进入工具/包管理器探测区。
- UltraMinimal 不再加载此文件。

### `profile.ps1`

- bootstrap 文件加载或模式判定失败时明确终止。
- Full/Minimal 必需定义、核心模块或环境初始化失败时，记录失败组件并执行 `Initialize-ProfileBootstrap`，将最终模式标记为 UltraMinimal fallback。
- Help、Install 和用户别名属于可选组件，失败只告警；Help/Install 在模式分流前以轻量定义加载，以满足对外函数兼容契约。
- 计时状态只由真实入口维护；正常运行保持安静，诊断模式才输出或写入结构化报告。

## Timing Design

- `profile.ps1` 是内部阶段与子步骤计时的唯一事实来源。
- 真实代码在关键操作前后记录耗时，不通过复制业务逻辑进行“重放”。
- `Debug-ProfilePerformance.ps1` 作为采样驱动器，为每个样本启动新的 `pwsh -NoProfile` 子进程，并让子进程执行真实 Profile。
- 报告区分：
  - `ProfileInternalMs`: Profile 内部阶段总计。
  - `ProcessElapsedMs`: 父进程观察到的完整子进程耗时。
- 结构化结果包含时间、平台、PowerShell 版本、模式、模式来源、阶段、子步骤、样本统计和限制说明。
- `-AsJson` 时 stdout 只输出 JSON；`-OutputPath` 使用 UTF-8 no BOM。
- 现有 `-SkipStarship/-SkipZoxide/-SkipProxy/-SkipAliases` 应继续可用于隔离 Full 模式步骤；如需向真实入口传递，使用明确的诊断参数，不复制初始化代码。

## Failure Matrix

| Failure | Behavior |
|---|---|
| encoding/bootstrap/mode 定义或模式判定失败 | 输出明确错误并终止 Profile 初始化 |
| platform context 构造失败 | 输出明确错误并终止，因为无法保证跨平台行为 |
| 必需 feature、核心模块或完整环境初始化失败 | 输出组件与原始错误，执行 bootstrap，最终模式标记为 UltraMinimal fallback |
| 用户别名配置失败 | 告警，使用空别名集合继续 |
| Help/Install 定义失败 | 告警，对应命令不可用，基础 Profile 继续 |
| OnIdle 单项失败 | 告警并继续其他 OnIdle 项；状态记录为部分失败或失败 |

## Compatibility

- `profile_unix.ps1` 继续转发 `profile.ps1`。
- `profile/loadModule.ps1` 作为历史兼容入口保留，内部适配新的平台上下文与加载函数。
- Full 的用户可见命令和初始化顺序保持兼容。
- Minimal 的同步核心模块保持兼容；有意移除的只有当前不会产生有效结果的工作。
- UltraMinimal 继续定义 Help、Install 和轻量 Environment 命令，但不解析完整 Environment 实现或加载 psutils。

## Test Strategy

- 纯函数测试：Windows/macOS/Linux 平台上下文矩阵。
- 加载计划测试：Full/Minimal/UltraMinimal 的文件、模块、别名和工具探测边界。
- 子进程测试：真实入口模式、降级输出、重复加载和结构化诊断。
- 静态测试：同步路径不得引用非核心 psutils 函数，README 与 OnIdle 实现一致。
- 性能验证：同一 macOS 主机、新进程、模式交替、至少 5 个样本；报告中位数、平均值、最小值和最大值，不写入 CI 绝对耗时断言。

## Rollback

- 新的 bootstrap/platform 层均为小型纯函数或幂等函数，可按文件回退。
- 保留兼容入口，避免安装路径与现有 `$PROFILE` 指向同时迁移。
- 若提前模式分流导致兼容问题，可临时恢复 Full/Minimal 的旧定义加载顺序，不影响平台上下文与诊断改进。
- 若 OnIdle 状态机在特定 PowerShell 版本不稳定，可回退为“仅检查当前订阅 ID”的较小幂等方案。
