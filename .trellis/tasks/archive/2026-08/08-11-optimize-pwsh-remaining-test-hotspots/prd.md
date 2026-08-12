# 继续优化 PowerShell 全量测试剩余热点

## Goal

在不降低 coverage 门槛、不删除真实入口/进程合同的前提下，继续压缩 Windows 本机 `pnpm test:pwsh:full` 耗时，并降低慢文件的环境波动。

## Background

- 上一任务三轮 coverage-on 墙钟为 329.48s、322.49s、298.67s，中位数 322.49s，coverage 62.46%。
- 已确认最有效的优化方式是减少真实子进程、重复模块导入和宿主命令发现，而不是 Pester 内置并行。
- 当前主要热点为 `install.Tests.ps1`、Windows/Linux entry smoke、`PackageSources.Tests.ps1` 及重复目录扫描/模块合同测试。
- 详细证据见 `.trellis/tasks/archive/2026-08/08-11-optimize-pwsh-full-test-duration/research/slow-points.md`。

## Requirements

- 优先优化 `psutils/tests/install.Tests.ps1`，隔离 `Install-Module`、仓库查询和命令发现等外部边界。
- 评估并收缩 Windows/Linux 入口 smoke 的重复进程启动，但保留参数解析、单文档 JSON、退出码和真实入口合同。
- 定位 `PackageSources.Tests.ps1` 的 17-29 秒波动来源，避免重复事务 fixture、模块导入或文件系统初始化。
- 检查 `docker.Tests.ps1`、`Install.Tests.ps1`、`moduleContract.Tests.ps1` 和 documentation 类测试的重复扫描与导入。
- 默认先做串行路径优化；未经单独设计，不引入外层并行分片。
- 不降低 50% coverage 门槛，不通过排除测试文件或删除关键端到端合同获得性能数字。
- 性能采样继续使用唯一 NUnit3/JSON artifact，禁止并发 Pester 污染样本。
- 固定本机、Docker 和 CI 使用的 Pester 版本，避免 `Install-Module Pester` 随 PSGallery 最新版漂移。
- 建立独立 Pester 6 PoC，验证文件级并行、`#pester:no-parallel`、Mock、TestDrive、coverage 和 NUnit 合同；PoC 不直接替换默认 full。
- 不采用 Pester 5 `CodeCoverage.UseBreakpoints = $false` 作为优化，因为探索实验出现 coverage 少采。
- 两阶段执行：阶段一继续优化串行热点并验证三轮中位数目标；阶段二升级到稳定版 Pester 6.0.1，验证串行兼容与 assertions 文件级并行合同。
- Pester 6 并行未通过 coverage、NUnit、隔离和清理合同前，默认 `test:pwsh:full` 保持串行；通过全部门禁后才允许提升为默认路径。
- 保留显式串行和 Pester 5.7.1 回退入口，升级失败时不要求卸载本机已有模块。
- Pester 6 完整诊断 PoC 固定使用已验证的 `ParallelThrottleLimit=2`；自动、2、4 三档正式性能对照转入后续优化任务，不以逻辑核数直接推断默认值。

## Acceptance Criteria

- [x] Windows host coverage-on 连续运行 3 轮，报告平均值、中位数、最慢值、coverage 和 Top 慢文件。
- [x] Coverage 不低于 50%，且现有真实 UTF-8、多流、Running、退出码和中断清理合同保持通过。
- [x] `psutils/tests/install.Tests.ps1` 典型耗时降低到 15 秒以内，或记录证据说明剩余成本不可安全移除。
- [x] 不引入新的 full 失败；既有 WSL guest 路径失败需单独标记，不能归因于本任务。
- [ ] `pnpm qa` 通过；Docker 不可用时 `pnpm test:pwsh:all` 继续快速失败并提示 fallback。
- [x] Pester 版本在本机安装入口、Docker 和 CI 中可复现；升级 PoC 可通过显式开关回退到 Pester 5.7.1。
- [ ] 阶段一完成后，Windows host coverage-on 三轮中位数不超过 290 秒，最慢值不超过 330 秒。当前桌面负载实测 Run 中位数 339.46 秒、最慢 345.58 秒，未通过。
- [ ] Pester 6.0.1 串行模式与 Pester 5.7.1 的测试发现数、失败集合、NUnit 字段和 coverage instruction/line 计数一致，或差异有明确兼容性解释并经测试锁定。
- [ ] Pester 6 并行模式下，共享宿主状态的文件使用 `#pester:no-parallel` 或等价隔离；连续运行不残留环境变量、TestDrive、模块或子进程。
- [x] assertions 并行完成完整诊断 PoC，记录 worker 崩溃、NUnit、失败集合和串行隔离限制；自动、2、4 三档正式对照转入后续优化任务。
- [x] Pester 6 内置并行与 CodeCoverage 不兼容的限制有源码/运行证据，默认 coverage full 保持串行，并创建外层 coverage 分片后续任务承接 `<=240s` 目标。

## Out of Scope

- 修复既有 WSL guest Windows 路径测试失败。
- 降低 coverage 门槛或扩大 coverage 排除列表来换取耗时。
- 未设计 coverage/NUnit 合并前直接并行运行多个 Pester full 分片。
- Pester 6 PoC 未证明可用前实现仓库级外层分片；它仅作为后续备选。

## Key Decisions

- 用户批准升级 Pester 并采用两阶段目标：串行 `<=290s`，Pester 6 并行 `<=240s`。
- Pester 6.0.1 在 CodeCoverage 开启时强制退回串行；当前任务不伪造并行 coverage 样本，`<=240s` 目标由 `.trellis/tasks/08-12-design-pwsh-coverage-sharding` 承接。
- 选择 PSGallery 稳定版 Pester 6.0.1，不采用 6.1.0 预发布版本。
- 不采用 Pester 5 profiler coverage tracer，因为实测覆盖计数少于 breakpoint tracer。
- Pester 版本、并行开关和默认入口必须可显式回退，禁止依赖 PSGallery 最新版漂移。
