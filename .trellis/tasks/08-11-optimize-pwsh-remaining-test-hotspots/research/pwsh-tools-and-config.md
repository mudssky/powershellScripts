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

## 2026-08-12 实施验证

### install.Tests 串行热点

- Pester 5.7.1、coverage off 的最坏基线墙钟为 74.42 秒。
- NUnit 显示三个 `Install-RequiredModule` 用例分别耗时 29.728、22.782、5.755 秒；详细输出确认伪模块名会因 Mock 作用域失效触发真实 PSGallery 查询。
- 将已安装、安装成功、安装失败三个场景合并到同一个 `InModuleScope`，一次注册外部边界 Mock，并验证顺序、状态、退出码、调用次数和失败后继续。
- 修复后两轮墙钟为 15.97 和 15.27 秒，40/40 通过；安装控制流用例耗时 0.595 秒。Pester 6 兼容调整后，Pester 5/6 双版本分别 17.85/18.29 秒，均 40/40 通过。

### Pester 6 coverage 限制

Pester 6.0.1 的 `Run.Parallel` 配置描述明确声明：启用 CodeCoverage 时文件级并行会回退串行。因此：

- assertions PoC 可以使用文件级并行。
- coverage full 不能依靠该能力达到并行目标。
- runner 对 `coverage + parallel` 明确报错，防止生成虚假并行性能结论。
- 默认 `test:pwsh:full` 继续指向串行入口；保留 Pester 5.7.1 回退。

小规模 assertions PoC 使用 Pester 6.0.1、throttle 2 运行两个配置/runner 文件，8/8 通过，总计 15.17 秒，控制台确认文件并行调度。该样本只证明开关与基本隔离，不代表 full 并行合同已经通过。

### 剩余热点复测

Pester 5.7.1、coverage off、独立 runner 墙钟：Linux entry 48.66 秒、Windows entry 33.68 秒、PackageSources 30.91 秒、docker 29.86 秒、Install 28.18 秒、moduleContract 25.51 秒、documentation 24.52 秒，全部通过。

后四个结构较小的文件仍接近 25 秒，说明独立 `pwsh`、Pester 导入和报告初始化是单文件测量的重要固定成本。未发现可以在不削弱入口/模块合同的前提下继续删除的明确重复工作，因此停止扩张测试重构，等待 full 的文件级 duration 数据决定下一步。

### 阶段一首轮 full 与 runner 固定成本

主会话在存在其他 Edge/browser-debug 负载的环境采集首轮 Pester 5.7.1 coverage full：墙钟 396.35 秒，Discovery 11.19 秒，Run 366.73 秒，coverage 62.52%，922 passed / 1 failed / 26 skipped。唯一失败仍是既有 WSL guest 路径用例；该样本受全局负载影响，不满足正式三轮性能采样条件。

该轮新增 `InvokePesterMode.Tests.ps1` 耗时 12.80 秒。原实现为四个合同分别启动真实 `pwsh`；改为一个隔离进程批量验证继承路径、显式路径、Pester 5 不支持并行和缺失版本后，Pester 5 单文件降到 7.68 秒，Pester 6 为 6.94 秒。runner 在目标版本已加载时也不再 `-Force` 重复导入。

### Pester 5/6 coverage 窄测差异

`install.Tests.ps1` 使用 JaCoCo、breakpoint coverage 的双版本窄测均通过断言，但计数不一致：

| Pester | covered | missed | percent |
|---|---:|---:|---:|
| 5.7.1 | 449 | 4263 | 9.53% |
| 6.0.1 | 344 | 4507 | 7.09% |

该单文件比例低于全量门槛是预期的，因为 coverage 路径覆盖全部 `psutils/modules/*.psm1`。计数差异说明 Pester 6 coverage 不能仅凭断言通过即视为与 5.7.1 等价；必须在相同静态 commit 和无并发负载下比较正式 full artifact。默认 full 保持串行，且在等价性解释完成前不提升 Pester 6 为正式 coverage 基线。

### Pester 6 完整 assertions 并行 PoC

- 首轮完整 PoC 在 `FormatPowerShellCode.Tests.ps1` 的临时仓库 `git add .` 处退出：Git 将 LF/CRLF 提示写入 stderr，Pester 6 worker 将其包装为 `RemoteException`。临时仓库固定 `core.autocrlf=false` 后，单文件并行 2/2 通过。
- 第二轮在既有 `WslSshAccess.Tests.ps1` Windows 路径失败处退出。该文件调用真实 Bash/WSL 边界并修改进程环境；实验性增加官方 `#pester:no-parallel` 后，失败可作为普通串行测试失败保留，不再导致 worker 崩溃。
- 使用该实验标记的第三轮 throttle 2 完整结束并生成 NUnit：Run 196.65 秒，920 passed、1 个既有 WSL failure、26 skipped。控制台额外显示 11 NotRun，是该文件在 parallel batch 的占位项；NUnit 中不存在漏跑测试。
- artifact：`tests/reports/pester-duration-2026-08-12T02-06-41-219Z.json` 及同名 XML。

该实验标记未保留：它会让 changed QA 选中并暴露当前任务明确排除的既有 WSL Windows 路径失败，而跳过或吞掉该失败会削弱测试合同。结论是 Pester 6 assertions 并行基础能力可用，但完整 full 并行仍被该既有用例阻塞，不能提升为默认或宣称稳定通过。coverage `<=240s` 需要外层独立 Pester 进程分片、JaCoCo/NUnit 合并与环境隔离，已创建 `.trellis/tasks/08-12-design-pwsh-coverage-sharding`，当前任务不自动实现。

### 2026-08-12 当前桌面负载三轮 coverage 验收

命令固定为：

```powershell
pwsh -NoProfile -NoLogo -NonInteractive -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 `
    -Mode full -Coverage On -PesterVersion 5.7.1
```

当前工作树发现 962 tests；桌面持续运行 VS Code、Edge、Orca、钉钉等进程，采样前 CPU 约 31%-59%，因此本组数据代表“当前桌面负载”，不是安静机器基线。三轮没有其他独立 full 测试介入，失败集合均为既有 WSL guest Windows 路径失败。

| 轮次 | Reporter 墙钟 | Pester Run | Discovery | Coverage | 结果 |
|---|---:|---:|---:|---:|---|
| 1 | 358.53s | 330.99s | 12.19s | 62.52% | 924 passed / 1 failed / 26 skipped |
| 2 | 374.64s | 345.58s | 12.03s | 62.52% | 924 passed / 1 failed / 26 skipped |
| 3 | 368.16s | 339.46s | 11.65s | 62.52% | 924 passed / 1 failed / 26 skipped |

- Reporter 墙钟：平均 367.11 秒，中位数 368.16 秒，最慢 374.64 秒。
- Pester Run：平均 338.68 秒，中位数 339.46 秒，最慢 345.58 秒。
- 阶段一 `Run <=290s`、最慢 `<=330s` 门禁未通过；coverage 与失败集合稳定，属于性能门禁失败，不是正确性回归。
- `install.Tests.ps1` 三轮为 11.70、12.44、8.92 秒，中位数 11.70 秒，已达到单文件目标，不再是首要热点。
- Top 中位数：LinuxInstallPipeline 29.24 秒、WindowsInstallEntrypoint 27.38 秒、docker 21.82 秒、PackageSources 20.76 秒、moduleContract 18.49 秒、Install 18.36 秒。

Artifacts：

- `tests/reports/pester-duration-2026-08-12T06-10-31-355Z.json`
- `tests/reports/pester-duration-2026-08-12T06-17-24-292Z.json`
- `tests/reports/pester-duration-2026-08-12T06-24-27-374Z.json`

验收同时发现 duration reporter 的 `pesterVersion` 使用机器最高已安装版本，导致显式运行 5.7.1 时错误记录为 6.0.1。reporter 已改为按命令参数、环境覆盖、仓库 `.pester-version`、已安装版本的顺序解析；上述三份 artifact 的版本元数据已校正为 5.7.1。
