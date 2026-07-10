# Profile Core 优化审计

## Goal

在保留 `profile.ps1` 统一入口和现有运行时平台隔离方式的前提下，优化 Profile 的启动加载顺序、平台策略组织、模式语义、重复加载行为、失败降级和性能诊断可信度。

## Background

- 当前 `profile.ps1` 是 Windows、macOS、Linux 的统一主入口，`profile_unix.ps1` 仅作兼容转发；用户确认继续采用该结构，不恢复两套完整入口。[`profile/README.md:9`](../../../profile/README.md) [`profile/profile_unix.ps1:3`](../../../profile/profile_unix.ps1)
- 平台差异散落在核心模块集合、Linux PATH 同步、包管理器和缓存标识等位置；本轮采用“拆平台策略、不拆入口”，集中描述差异但不复制公共执行链。[`profile/core/loadModule.ps1:11`](../../../profile/core/loadModule.ps1) [`profile/features/environment.ps1:408`](../../../profile/features/environment.ps1) [`profile/features/environment.ps1:461`](../../../profile/features/environment.ps1)
- 主入口在模式判定前无条件加载 6 个 core/feature 文件，导致 UltraMinimal 仍解析 Help、Install 和完整 Environment 定义。[`profile/profile.ps1:31`](../../../profile/profile.ps1) [`profile/profile.ps1:58`](../../../profile/profile.ps1)
- 2026-07-11 在 macOS Darwin 25.5.0、PowerShell 7.5.4 上，以新 `pwsh -NoProfile` 进程交替采样真实入口 5 次：Full 中位数 `411ms`，Minimal `290ms`，UltraMinimal `200ms`；UltraMinimal Phase 1 中位数 `154ms`，约占总耗时 77%。该数据只作为当前主机的实施前基线，不代表 Windows/Linux。
- `Debug-ProfilePerformance.ps1` 手工复制 Phase 3/4，没有调用真实加载器与 `Initialize-Environment`，已经与模式行为漂移，不能用于可靠的模式间对比。[`profile/Debug-ProfilePerformance.ps1:163`](../../../profile/Debug-ProfilePerformance.ps1) [`profile/Debug-ProfilePerformance.ps1:197`](../../../profile/Debug-ProfilePerformance.ps1)
- Minimal 虽设置 `SkipTools` 和 `SkipAliases`，仍探测全部工具与包管理器，并读取不会注册的用户别名配置。[`profile/features/environment.ps1:392`](../../../profile/features/environment.ps1) [`profile/features/environment.ps1:465`](../../../profile/features/environment.ps1) [`profile/core/loaders.ps1:20`](../../../profile/core/loaders.ps1)
- 同一会话连续加载两次 Profile 会留下两个 `PowerShell.OnIdle` 订阅。[`profile/core/loadModule.ps1:66`](../../../profile/core/loadModule.ps1)
- 当前测试未覆盖平台策略矩阵、加载器模式分支、重复 OnIdle 注册和诊断与真实入口的一致性；README 中的核心模块数量与 OnIdle 示例也已漂移。[`tests/ProfileMode.Tests.ps1:10`](../../../tests/ProfileMode.Tests.ps1) [`tests/DeferredLoading.Tests.ps1:108`](../../../tests/DeferredLoading.Tests.ps1) [`profile/README.md:42`](../../../profile/README.md) [`profile/README.md:225`](../../../profile/README.md)

## Requirements

- R1：保留 `profile.ps1` 统一入口与 `profile_unix.ps1` 兼容 shim，不新增 Windows/Unix 两套完整执行链。
- R2：新增集中式平台上下文，统一提供平台标识、Unix 能力、同步核心模块、包管理器、PATH 同步策略、缓存标识和路径比较规则；公共逻辑消费上下文，不重复判断平台。
- R3：模式判定必须早于重量级 Environment 与 loaders 加载；UltraMinimal 只加载编码、仓库路径、模式诊断和对外兼容函数所需的轻量定义。
- R4：Minimal 保持全部现有同步核心模块在启动返回后立即可用，但不得读取用户别名配置，也不得执行工具/包管理器探测、工具初始化或安装提示。
- R5：Full 保持现有工具、别名、代理、环境变量和跨平台行为；平台策略集中后不得改变各平台的功能集合。
- R6：OnIdle 注册在同一会话重复加载 Profile 时必须幂等；已有待执行或已完成状态不得产生重复模块导入与快捷键注册。
- R7：性能诊断必须执行真实 Profile 调用链，区分内部阶段耗时与外部进程耗时，并输出平台、PowerShell 版本、模式、样本数、平均值、中位数、最小值、最大值和限制说明。
- R8：采用显式分级降级：可选别名、Help、Install 和 OnIdle 失败时告警并跳过；必需核心模块或完整环境初始化失败时告警并降级到 UltraMinimal；bootstrap 或模式判定失败时明确终止初始化。
- R9：新增或修改的函数必须包含中文 comment-based help，明确核心功能、参数和返回值；不在本轮全面数据驱动重写 `mode.ps1` 或清理未触及的历史函数。
- R10：补齐平台、模式、幂等、降级和诊断契约测试，并同步 README 与实际模块数量、加载流程和 OnIdle 实现。
- R11：性能结论必须按平台与模式分别报告，不把 macOS 数据外推到 Windows/Linux，不在 CI 中设置脆弱的绝对毫秒门槛。

## Acceptance Criteria

- AC1（R1-R2）：`profile.ps1` 仍为统一入口；Windows、macOS、Linux 的平台上下文可通过纯函数测试，各自返回预期模块、包管理器、PATH 策略和缓存标识。
- AC2（R3）：UltraMinimal 不加载 `loaders.ps1`、`features/environment.ps1` 或 psutils 模块，但仍正确设置 UTF-8、`POWERSHELL_SCRIPTS_ROOT`、仓库 `bin` PATH，并保留 `Show-MyProfileHelp`、`Initialize-Environment`、`Set-PowerShellProfile` 对外函数。
- AC3（R4）：Minimal 启动后现有同步核心模块仍立即可用；用户别名配置、`Find-ExecutableCommand`、工具初始化和安装提示均未执行。
- AC4（R5）：Full 在 macOS 本机通过现有 Profile 行为测试；Windows/Linux 平台策略通过单元测试，运行态覆盖依赖 CI 或 WSL/Docker。
- AC5（R6）：同一进程连续加载 Profile 两次后，Profile 自己管理的 `PowerShell.OnIdle` 订阅最多一个。
- AC6（R7）：诊断报告来自真实入口；报告中的模式和阶段总计与 Profile 运行时记录一致，支持至少 5 次新进程采样并给出统计摘要。
- AC7（R8）：可选组件失败不会终止基础 Profile；核心模块或完整环境初始化失败会输出组件、原始错误和降级模式；bootstrap/模式判定失败会明确终止。
- AC8（R9-R10）：新增测试覆盖平台矩阵、Full/Minimal/UltraMinimal 加载计划、重复加载、失败分级和诊断输出；README 不再包含已知模块数量或 `.GetNewClosure()` 漂移。
- AC9（R11）：在同一 macOS 主机按交替顺序复测各模式至少 5 次；UltraMinimal Phase 1 和总耗时应低于本轮基线，Minimal Phase 4 应低于本轮基线，Full 中位数不得出现超过 10% 的回归。该阈值只用于本地变更评估，不进入 CI。
- AC10：根目录 `pnpm qa` 与 `pnpm test:pwsh:all` 通过；若 Docker 不可用，至少执行 `pnpm test:pwsh:full` 并注明 Linux 覆盖依赖 CI 或 WSL。

## Out of Scope

- 不恢复或维护 Windows/Unix 两套完整 Profile 入口。
- 不改变 Minimal 的“核心模块立即可用”契约。
- 不全面重写 `mode.ps1` 的重复决策对象构造。
- 不全面补齐未触及历史函数的帮助文档。
- 不优化安装器、应用安装清单或与 Profile 启动链无关的脚本。
- 不将当前 macOS 性能数字设为跨机器或 CI 的绝对门槛。
