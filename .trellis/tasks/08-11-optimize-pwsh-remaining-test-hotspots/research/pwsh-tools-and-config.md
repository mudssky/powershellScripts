# PowerShell/Pester 工具与配置提速研究

## 当前环境

- Windows PowerShell host：PowerShell 7.6.3
- 本机 Pester：5.7.1
- Pester 5.7.1 `Run` 配置没有 `Parallel` 属性，当前按 container 串行执行。
- PSGallery 当前存在稳定版 Pester 6.0.1，发布时间为 2026-07-18；Pester 6 文档将文件级并行标记为实验特性。
- 将 Pester 6.0.1 保存到隔离目录并实际导入后，确认 `Run` 包含 `Parallel` 和 `ParallelThrottleLimit`；默认值分别为 `false` 和 `0`。

## 候选方案

### 1. Pester 6 文件级并行

Pester 6 支持通过 `Run.Parallel` 按测试文件并行，并允许使用 `#pester:no-parallel` 将共享宿主状态的文件留在父会话。

稳定版 6.0.1 的实测配置属性包括 `Parallel`、`ParallelThrottleLimit` 和 `RepoRoot`，因此 PoC 不需要采用 6.1.0 预发布版本。

潜在收益：当前 full 有多个 12-33 秒的独立慢文件，文件级并行是最可能把中位数显著压到 240 秒以内的工具能力。

限制与风险：

- 该能力仍标记为实验特性。
- 需要验证 Mock、`InModuleScope`、TestDrive、环境变量、模块状态和进程清理兼容性。
- 需要确认 coverage 和 NUnit 输出在并行模式下的完整性。
- CI、Docker 和本机当前没有固定 Pester 版本；升级实验前应先建立版本矩阵和回滚入口。

结论：建立独立 Pester 6 PoC，不直接替换默认 full。

### 2. 外层分片 runner

使用 Node.js 或 PowerShell runner 将互不共享状态的测试文件分组到多个独立 `pwsh -NoProfile` 进程，每个 lane 使用唯一 NUnit/coverage/TestDrive 路径。

优点：不依赖 Pester 6 实验 API，调度和 `no-parallel` 分组由仓库控制。

代价：必须实现 NUnit 汇总、coverage 合并、退出码聚合、中断清理和 lane 负载均衡。coverage 合并完成前，只适合 assertions lane，不能替代正式 coverage full。

结论：作为 Pester 6 PoC 失败时的备选，不进入第一批串行优化。

### 3. Coverage profiler tracer

Pester 5.7.1 支持：

```powershell
$config.CodeCoverage.UseBreakpoints = $false
```

该配置从断点 coverage 切换到 profiler tracer。针对 `psutils/tests/install.Tests.ps1` 的探索样本：

| 模式 | 墙钟 | Instruction covered | Line covered |
|---|---:|---:|---:|
| Breakpoints 冷样本 | 56.72s | - | - |
| Breakpoints 热验证 | 50.85s | 442 | 339 |
| Profiler | 50.07s | 329 | 235 |

热样本耗时差仅约 1.5%，但 profiler 少记录 113 条 instruction 和 104 行，coverage 语义不一致。

结论：拒绝作为提速配置，除非后续 Pester 版本修复并证明覆盖计数一致。

### 4. Fail-fast 与输出配置

- `Run.SkipRemainingOnFailure` 只能缩短失败构建，不会改善绿色 full 的中位数。
- `Output.Verbosity=None`、`RenderMode=Plaintext`、`pwsh -NoLogo -NonInteractive` 可减少少量渲染和启动开销，但相对 300 秒级 Run 不是主要收益。
- `Run.Path` 精确收缩已用于 QA changed 模式，适合开发反馈，不可替代 full 门禁。

结论：fail-fast 可作为 CI 失败反馈优化；输出和启动参数只做低风险微优化 benchmark。

### 5. 模块发现配置

- 对完全显式导入的测试 lane，可实验 `$PSModuleAutoLoadingPreference = 'None'`，减少隐式模块发现。
- 该配置可能破坏依赖自动加载的测试，必须先通过静态搜索和单独 lane 验证。
- 相比全局禁用，继续使用显式模块路径、共享 `BeforeAll` 导入和能力 snapshot 风险更低。

结论：只在明确的测试分片中实验，不设置为全局默认。

## 推荐顺序

1. 继续处理 `install.Tests.ps1` 等串行热点，目标中位数不超过 290 秒。
2. 固定本机、Docker、CI 的 Pester 版本，避免 PSGallery 最新版漂移。
3. 建立 Pester 6 独立 PoC，对比串行/并行 assertions 与 coverage 合同。
4. Pester 6 不满足兼容性时，再设计仓库级外层分片。
5. 不采用 Pester 5 profiler coverage 提速。

## 资料来源

- Pester 文档：`/pester/docs`，parallel、code coverage 和 skip-on-failure 配置说明。
- PSGallery：Pester 6.0.1 稳定版元数据。
- 本机 `New-PesterConfiguration` 与 A/B 实验结果。
