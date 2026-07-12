# 审计 psutils 包优化项

## Goal

系统审计 `psutils` 包当前实现，识别真正值得投入的优化项，并形成按价值、风险和实施成本排序的可执行规划，避免仅基于代码风格进行无收益重构。

## Background

- `psutils` 是仓库内共享的 PowerShell 工具包，包含聚合模块、多个 nested module、配置解析源码、示例、文档及包内 Pester 测试。
- 现有 Trellis 规范已明确共享配置解析器和 WSL Docker wrapper 的行为契约；审计不能破坏这些兼容性要求。
- 本阶段只做证据驱动的分析与规划，不修改 `psutils` 生产代码。
- 兼容目标确定为 PowerShell 7.4+ / Core。官方 `CompatiblePSEditions` 只声明已验证的兼容性，不会自动在 Desktop/Core 间选择实现；为 5.1 保留单包兼容需要增加 5.1 可解析的 RootModule loader、隔离 edition-specific 文件并长期维护双测试矩阵，当前没有足够收益。若未来出现明确 5.1 消费者，再评估独立 legacy 包，而不是让主包长期使用最低共同语法。
- manifest 声明兼容 Desktop 与 PowerShell 5.1，但源码已使用 PowerShell 7 语法或 API，包括 null conditional、null coalescing 和 `ConvertFrom-Json -AsHashtable`；当前 CI 也只通过 `pwsh` 验证，实际兼容边界与元数据不一致。[`psutils/psutils.psd1:22`](../../../psutils/psutils.psd1) [`psutils/psutils.psd1:40`](../../../psutils/psutils.psd1) [`psutils/modules/hardware.psm1:44`](../../../psutils/modules/hardware.psm1) [`psutils/modules/oss.psm1:808`](../../../psutils/modules/oss.psm1) [`psutils/modules/json.psm1:38`](../../../psutils/modules/json.psm1)
- `psutils/index.psm1` 仅剩注释，但仍被模型下载脚本和树示例当作入口；实际运行 `ai/downloadModels.ps1 -ListOnly` 会连续缺失 `Get-OperatingSystem`、`Get-GpuInfo` 和 `Get-SystemMemoryInfo`。[`psutils/index.psm1:1`](../../../psutils/index.psm1) [`ai/downloadModels.ps1:71`](../../../ai/downloadModels.ps1) [`ai/downloadModels.ps1:377`](../../../ai/downloadModels.ps1) [`psutils/examples/tree-examples.ps1:14`](../../../psutils/examples/tree-examples.ps1)
- 聚合 manifest 声明 130 个函数项，实际导入只得到 128 个命令：不存在的 `Test-ModuleFunction` 被列为导出，两套不同参数契约的 `New-Shortcut` 被静默合并为 `win.psm1` 实现。[`psutils/psutils.psd1:126`](../../../psutils/psutils.psd1) [`psutils/psutils.psd1:157`](../../../psutils/psutils.psd1) [`psutils/psutils.psd1:159`](../../../psutils/psutils.psd1) [`psutils/modules/functions.psm1:304`](../../../psutils/modules/functions.psm1) [`psutils/modules/win.psm1:63`](../../../psutils/modules/win.psm1)
- 配置规范将 `Read-ConfigEnvFile` 定义为公共 source reader，但 `config.psm1` 和聚合 manifest 均未导出它，规范、实现和可发现 API 已漂移。[`.trellis/spec/psutils/package/shared-config-resolver.md:20`](../../../.trellis/spec/psutils/package/shared-config-resolver.md) [`psutils/modules/config.psm1:16`](../../../psutils/modules/config.psm1) [`psutils/psutils.psd1:109`](../../../psutils/psutils.psd1)
- 包级 QA/full 均发现 422 项测试，当前平台执行结果为 396 通过、3 跳过、23 未运行；测试主要单独导入子模块，没有覆盖聚合入口、manifest 导出完整性、同名命令冲突或示例可执行性。[`psutils/tests/test.Tests.ps1:2`](../../../psutils/tests/test.Tests.ps1) [`psutils/tests/functions.Tests.ps1:194`](../../../psutils/tests/functions.Tests.ps1) [`psutils/tests/win.Tests.ps1:29`](../../../psutils/tests/win.Tests.ps1)
- 本机 PowerShell 7.5.4 重复导入基线中，聚合 manifest 中位数约 `175ms`，而 `config.psm1` 约 `1ms`；Profile 已有同步轻量子模块与 OnIdle 全量加载设计及性能守卫，因此应保留现有按消费者分层导入策略，不先引入新的自定义懒加载框架。[`profile/core/loadModule.ps1:25`](../../../profile/core/loadModule.ps1) [`profile/core/loadModule.ps1:66`](../../../profile/core/loadModule.ps1) [`profile/profile.ps1:261`](../../../profile/profile.ps1)
- 公共面目前有 129 个唯一导出名，其中 69 个在仓库 PowerShell 调用 AST 中没有消费者；该数据不能证明外部交互式使用不存在，但足以要求区分稳定公共 API、兼容 API、诊断命令和内部 helper。`wrapper.psm1`、`string.psm1` 仍使用通配符导出，且 wrapper 导入会写入全局变量。[`psutils/modules/wrapper.psm1:3`](../../../psutils/modules/wrapper.psm1) [`psutils/modules/wrapper.psm1:270`](../../../psutils/modules/wrapper.psm1) [`psutils/modules/string.psm1:142`](../../../psutils/modules/string.psm1)
- README、帮助模块与示例存在明显漂移：README 声称 15 个模块按需加载、每个函数都有完整帮助、仍介绍不存在的 ffmpeg 模块且版本写为 0.0.1；4 个缓存 demo 和树示例使用失效导入路径；已弃用的 `Search-ModuleHelp` 仍被 README 和其他导出函数作为主路径使用。[`psutils/README.md:60`](../../../psutils/README.md) [`psutils/README.md:61`](../../../psutils/README.md) [`psutils/README.md:407`](../../../psutils/README.md) [`psutils/README.md:502`](../../../psutils/README.md) [`psutils/demo/cache-performance-demo.ps1:21`](../../../psutils/demo/cache-performance-demo.ps1) [`psutils/modules/help.psm1:92`](../../../psutils/modules/help.psm1)
- 对 manifest 导出定义做帮助元数据检查后，9 个函数完全缺少 comment-based help、18 个缺少 `.OUTPUTS`、8 个参数说明不完整，与项目公共接口注释规则不一致。

## Requirements

- R1：主包正式要求 PowerShell 7.4+ / Core，并同步 manifest、README、入口错误提示和 CI 运行时假设；本轮不创建 Windows PowerShell 5.1 双包或兼容 loader。
- R2：以 `psutils.psd1` 为规范入口，将 `index.psm1` 改为弃用 shim，并迁移所有仓库消费者与示例。
- R3：建立可执行的 manifest/API 契约测试，检测不存在的导出、重复命令名、参数契约覆盖、规范声明与实际导出的漂移。
- R4：对 129 个唯一导出名分层，优先收紧 wildcard 导出、全局变量和明显内部 helper；README、Profile 和常用交互命令保持兼容，已文档化命令使用参数 alias、wrapper 或弃用期迁移。
- R5：保持 Profile 现有同步轻量加载和 OnIdle 全量加载边界，只对有测量证据的导入或热路径做性能优化。
- R6：修复 README、帮助、docs、examples 和 demo 的事实漂移，并增加无副作用的示例 smoke test 或可发现性检查。
- R7：按项目规范补齐保留公共接口的核心功能、参数和返回值说明；不要求一次性润色所有内部函数。
- R8：对 `functions.psm1`、`help.psm1`、`test.psm1` 等职责混杂模块做边界评估，但只有在减少冲突、加载成本或维护风险时才拆分。
- R9：所有优化建议必须附带源码、测试、配置、文档或历史证据，并按缺陷、兼容、性能、维护和清理分类，说明收益、不处理风险、实施依赖和验证方式。

## Task Map

| 子任务 | 优先级 | 交付边界 | 依赖 |
|---|---|---|---|
| `07-12-psutils-core-contract` | P0 | PowerShell 7.4+ 声明、唯一入口、manifest/API 契约、真实消费者迁移 | 无，优先实施 |
| `07-12-psutils-docs-examples` | P1 | README、帮助、docs、examples、demo 与可执行性检查 | 等核心契约确定入口与函数名 |
| `07-12-psutils-api-boundaries` | P2 | 公共 API 分层、wildcard/global 状态收敛、模块职责与弃用策略 | 等核心契约建立基线；受兼容策略决策约束 |
| `07-12-psutils-runtime-hardening` | P2 | 敏感参数、动态执行、静默异常、自动变量与跨平台健壮性 | 等核心契约和 API 边界完成后实施 |

父任务只维护审计结论、任务映射和跨任务验收，不直接承载生产代码实施。子任务按表中依赖独立规划、启动、验证和归档。

## Acceptance Criteria

- [ ] 覆盖 `psutils/index.psm1`、manifest、`modules/**`、`src/**`、`tests/**`、包脚本、文档和示例。
- [ ] 每个入选优化项都有具体 `file:line` 证据、影响说明、建议方案、风险等级和验证建议。
- [ ] 给出明确的优先级分层，并说明哪些观察项不值得当前投入。
- [ ] 对复杂优化形成 `design.md` 和 `implement.md`，包含边界、兼容性、执行顺序、验证命令和回滚点。
- [ ] PRD 最终只保留尚未解决的产品意图或范围问题，并通过用户审阅后再进入实施。
- [ ] 四个子任务均有独立、可测试的验收标准，且依赖关系写入各自规划产物。
- [ ] P0 核心契约先完成；后续子任务不重复修改已确定的入口和兼容边界。

## Out of Scope

- 未经用户批准直接实施优化。
- 与 `psutils` 无调用或契约关系的仓库级重构。
- 仅为统一个人风格而进行的大规模格式化或重命名。
