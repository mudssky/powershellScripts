# 优化测试隔离与执行性能

## 目标

降低 PowerShell/Pester 测试，尤其是 package source 与换源相关测试的执行耗时和控制台噪声；测试默认不得依赖真实网络、真实镜像可用性或本机包管理器状态，同时保留对事务、回滚、探活策略和外部命令契约的有效覆盖。

## 背景与已确认事实

- `tests/PackageSources.Tests.ps1` 覆盖 package source CLI、China/Auto 策略、chsrc adapter、系统 source snapshot 与 Docker adapter，是当前重点审计对象。
- 该文件已有多处 `Invoke-WebRequest` Mock，说明“存在网络相关逻辑”不等于测试一定访问真实网络；仍需追踪未 Mock 分支和子进程边界。
- package source 测试大量通过子 `pwsh` 调用真实 CLI，并创建、恢复、删除临时事务状态；冷启动与文件清理可能比被测业务逻辑更昂贵。
- 本机 macOS、`pwsh -NoProfile`、单文件三次样本为 39.64s、39.37s、39.48s，中位数 39.48s，波动很小，说明耗时来自确定性测试结构而非偶发网络抖动。
- 最慢用例为 `Ensure 将后出现的 npm 补进既有 China 事务`，三次均约 5.3s；多个 Apply/Restore/Status 场景稳定在 2.3–3.9s。
- fake chsrc 与 fake npm 当前均生成 `.ps1` 文件；每次 adapter 调用会启动额外 PowerShell 进程，叠加 CLI 测试自身的子 `pwsh` 冷启动。
- 完整 `pnpm test:pwsh:qa` 本机样本为 102.74s；最慢文件依次为 PackageSources 38.34s、InstallOrchestrator 24.68s、MacOSInstallPipeline 10.61s、LinuxInstallPipeline 10.15s、WindowsInstallPipeline 6.72s。
- PackageSources 单文件约占 QA 总耗时 37%，是最大且边界清晰的优化目标。
- 本次 macOS QA 完整日志未出现 `Removed ... files`；该输出尚不能归因于 package source 单测，需在 full/Linux 容器或产生该输出的原命令中继续定位。
- 用户观察到多行 `Removed 2 of 2 files [...]` 进度输出，要求定位来源并消除不必要的真实 I/O 或噪声。
- 既有性能经验要求：快速测试 fixture 不使用高启动成本解释器进程；优先使用平台原生命令或进程内调用。

## 需求

- R1：建立可重复的测试性能基线，至少包含 package source 单文件耗时、慢测试排序与完整 QA 中的占比。
- R2：继续在 full/Linux 日志中定位 `Removed ... files` 输出的具体命令和调用链；若确认不属于 PackageSources 范围，则记录证据并拆为后续事项，不通过隐藏 stdout 掩盖未知副作用。
- R3：默认测试禁止访问真实公网或真实镜像端点；网络成功、失败、超时和回退由可控 Mock/fixture 表达。
- R4：减少不必要的 `pwsh` 子进程、重复模块导入、重复 catalog 解析和大规模临时目录清理，同时保持 CLI 集成边界的代表性测试。
- R5：区分进程内单元测试与少量端到端 CLI 测试；同一行为不在多个子进程用例中重复验证。
- R6：性能优化不得降低 China/Auto 事务、drift、orphan、rollback、adapter 和敏感信息保护的行为覆盖。
- R7：控制台输出保持安静且可诊断；预期失败和清理过程不输出下载/删除进度条。
- R8：在同一机器、同一命令和 3 次样本口径下，`PackageSources.Tests.ps1` 中位数不高于 20 秒，且相对 39.48 秒基线至少提升 45%。
- R9：本期范围限定为 `PackageSources.Tests.ps1`、其直接测试 fixture，以及为支持进程内测试所必需的 package source 测试接口；不同时重构 InstallOrchestrator 或平台安装流水线测试。
- R10：真实 CLI 子进程测试收敛为少量接口合同用例，覆盖参数解析、JSON/退出码、WhatIf 映射和 legacy Docker 兼容；事务与 adapter 行为通过进程内 `Invoke-PackageSourceAction` 测试。
- R11：新增可手动运行的 package source 测试性能 benchmark/报告入口，输出平台、PowerShell 版本、样本、平均值、中位数和最慢值；CI 只验证契约，不使用绝对耗时门槛。

## 验收标准

- [ ] 有优化前后使用同一命令、同一环境和多次样本的耗时对比，报告中位数、平均值和最慢值。
- [ ] `PackageSources.Tests.ps1` 的 3 次样本中位数 ≤20 秒且提升 ≥45%。
- [ ] package source 相关测试默认零真实网络访问，并有自动化断言防止未 Mock 网络边界回归。
- [ ] PackageSources 单测和 macOS QA 不产生下载/删除进度输出；`Removed ... files` 若仅能在范围外路径复现，需记录来源或明确的后续定位命令。
- [ ] 慢测试列表中的主要热点已被解释并处理，或明确记录为保留的必要集成成本。
- [ ] package source 单文件及 `pnpm qa`/适用 PowerShell 全量门禁通过。
- [ ] 关键事务和错误路径覆盖保持不变或增强。

## 范围外

- 不以删除关键测试、降低断言强度或扩大 Skip 标签来换取速度。
- 不在默认性能测试中探测真实镜像或对公网质量做结论。
- 不把单台机器的绝对毫秒阈值设为脆弱 CI 门禁。
- 不在本期优化 InstallOrchestrator、macOS/Linux/Windows 安装流水线的子进程冷启动。
