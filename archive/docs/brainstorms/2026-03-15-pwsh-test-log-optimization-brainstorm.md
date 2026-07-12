---
date: 2026-03-15
topic: pwsh-test-log-optimization
---

# 基于 test.log 的 PowerShell 测试进一步提速与输出收口

## What We're Building

这次要解决的是 `pnpm test:pwsh:all` 在已经完成上一轮稳定性修复之后，仍然暴露出来的两类剩余问题：

1. 总墙钟时间仍然被少数热点测试文件拉高。
2. 默认通过日志里仍混入 `WhatIf`、`WARNING:`、脚本自带 `Write-Host` 等非断言输出，影响快速确认“到底有没有过”和“慢点在哪”。

基于当前 `test.log`，两路 full 已经都能完整跑完，但聚合命令的总时长基本被较慢的一路锁死：

- host `Tests completed in 39.05s`
- linux `Tests completed in 40.4s`

这意味着接下来的优化不能只盯 Windows 或只盯 Linux；只有命中双平台共享热点，才会明显降低 `pnpm test:pwsh:all` 的真实体感时间。

## Why This Approach

当前日志已经足够说明下一轮该打哪里，而不是继续泛泛地讲“优化测试”：

- 共享热点最明显的是 `psutils/tests/help.Tests.ps1`、`tests/Invoke-Benchmark.Tests.ps1`、`psutils/tests/cache.Tests.ps1`。
- 其中 `help.Tests.ps1` 在 Linux 上达到 `18.1s`，已经是整条链路的主导瓶颈；它内部包含 `Test-HelpSearchPerformance`，会实际跑一轮“自定义解析 vs Get-Help”性能对比，这更像诊断/基准而不是常规门禁断言。
- `Invoke-Benchmark.Tests.ps1` 在 host `8.33s`、linux `5.65s`，主要成本来自每个 `It` 都拉起新的 `pwsh -NoProfile -File` 子进程做端到端调用；它验证价值高，但当前实现粒度偏重。
- `cache.Tests.ps1` 双平台都在 `5s` 左右，说明这里既有文件 IO，也有 `Start-Sleep` 一类真实时间等待，属于中优先级热点。
- 当前日志共有 `32` 行 `What if:`，其中绝大多数来自 `Sync-PathFromBash` 对缓存目录与 PATH 预演的重复提示。额外还有 `3` 条 `WARNING:`，来源集中在 `env.Tests.ps1` 与 `web.Tests.ps1`。
- 一个关键事实是：`WhatIf` 提示不能靠 `6>$null`、`$WarningPreference='SilentlyContinue'` 或 `$InformationPreference='SilentlyContinue'` 静音。也就是说，剩余 `WhatIf` 噪音不是“流重定向还没写够”，而是测试边界本身需要重构。
- 在 2026-03-15 的一轮实测中，当前 `pnpm test:pwsh:all` 外层墙钟约为 `50.62s`；仅通过环境变量关闭 host coverage（Linux 维持现状）后，同等命令下降到 `37.72s`。两组日志里的 `host Tests completed in` 分别约为 `30.59s` 与 `31.5s`，说明节省的 `12.9s` 主要不在测试文件本身，而在 host coverage 收尾与结果处理路径。

仓库今天新增的 solution 已经把更早一批热点（例如 `install.Tests.ps1`、`hardware.Tests.ps1`、`test.Tests.ps1`）压下去了，所以这次讨论的是“第二梯队剩余空间”，不是重复上一轮工作。

## Approaches Considered

### Approach A: 保持 full 语义不变，继续瘦身剩余热点并在测试层收口噪音

保持 `pnpm test:pwsh:all` 继续是 `host full + linux full` 的提交门禁，不改命令语义；优先处理共享热点，并把默认通过日志中的非断言输出继续压回测试边界。

**Pros:**

- 不需要重新解释 `qa`、`full`、`all` 的职责边界。
- 最符合当前仓库已经形成的测试语义。
- 对共享热点下手后，能同时降低 host 与 linux 的体感耗时。

**Cons:**

- 需要分别处理 `help`、`benchmark`、`cache`、`profile`、`env` 等多处剩余边界。
- 一些最有效的提速点最终还是会逼近“是否把诊断型测试移出 full”这个语义问题。

**Best when:** 你希望默认提交流程保持现状，只接受测试内部实现、mock 边界和输出策略的优化。

### Approach B: 保持执行集不变，但把默认控制台改成“摘要优先”，详细日志只在失败或 debug 模式展开

继续执行同样的 host / linux full 集合，但把原始输出先按 lane 收集，再只打印文件级摘要、失败详情和最终汇总；低价值通过日志默认不直接刷屏。

**Pros:**

- 对可读性改善最快。
- 不需要先触碰具体测试实现。
- 可以和后续热点提速并行推进。

**Cons:**

- 基本不解决真实执行时长。
- 实时观察感会变弱，调试路径需要额外设计。
- 如果测试本身仍在输出大量 host 文本，只是把噪音“藏起来”，不是根因修复。

**Best when:** 你当前最痛的是“日志难看”，而不是“等待太久”。

### Approach C: 把明显诊断型 / 基准型测试从默认 full 门禁中拆出去

明确承认有些测试更像基准或交互链路演示，不适合作为每次提交都跑的 full 门禁内容。例如 `Test-HelpSearchPerformance` 这种“性能对比能否跑通”的断言，可以移到 `Slow`、`debug` 或单独 benchmark 命令。

**Pros:**

- 对总时长的改善最大，尤其能直接打掉 Linux 上 `help.Tests.ps1` 的主热点。
- 也能顺手减少不少默认输出噪音。
- 有利于把“功能正确性”与“诊断/基准观察”分层。

**Cons:**

- 这已经不是单纯提速，而是调整门禁覆盖边界。
- 需要额外约定这些测试以后在哪条命令里兜底。
- 如果边界划错，可能让某些真实回归延后暴露。

**Best when:** 你接受 `full` 只保留稳定、高信号的功能断言，而把性能展示、交互演示型用例下沉到专门入口。

## Recommendation

推荐 **Approach A** 作为主线，但对极少数“明显更像诊断而不是门禁断言”的测试，预留 **Approach C** 的收口空间；同时把 host coverage 从默认 `all` 关键路径中拆出，单独提供 `pnpm test:pwsh:coverage`。

原因很直接：

- 当前 `test:pwsh:all` 的墙钟时间由 host `39.05s` 和 linux `40.4s` 共同决定，优先打共享热点最有效。
- 仅移除 host coverage 就能让 `pnpm test:pwsh:all` 外层墙钟从 `50.62s` 降到 `37.72s`，这是当前最确定、收益最大的外层优化点。
- `WhatIf` 残余噪音已经证明不能再靠重定向补丁解决，必须从测试设计上收口。
- `WARNING:` 残余只剩少数明确来源，属于低风险、可快速收口的问题。
- 真正可能需要你拍板的，只剩“`help.Tests.ps1` 里的性能对比测试是否继续留在默认 full”这一类边界问题。

## Key Decisions

- 下一轮优化优先级应从“只看 host 热点”改为“优先看双平台共享热点”，否则 `all` 的真实体感时间降不下来。
- 默认 `pnpm test:pwsh:all` 应改为“host 功能断言（不含 coverage）+ linux full”并发门禁；coverage 改由单独的 `pnpm test:pwsh:coverage` 承担。
- `help.Tests.ps1` 是当前第一优先级，因为它同时兼具“单文件极慢”和“更偏诊断型断言”两个特征。
- `Test-HelpSearchPerformance` 不再留在默认 `test:pwsh:full` / `test:pwsh:all` 门禁中，改由 benchmark 入口承接。
- `Invoke-Benchmark.Tests.ps1` 的主要空间不在 Pester 配置，而在测试实现粒度过重；应优先减少重复子进程拉起次数或把非必要端到端路径下沉。
- `cache.Tests.ps1` 的优化空间主要在真实等待与文件系统副作用隔离，不在简单日志压制。
- 默认 full 日志里的 `WhatIf` 残余不应再靠流重定向修补；要么避免默认 full 里跑真实 `-WhatIf` 文案路径，要么改成更可控的断言边界。
- `env.Tests.ps1` 与 `web.Tests.ps1` 的剩余 warning 属于低风险快修项，应和热点提速并行处理，而不是留到最后。

## Resolved Questions

- 是否接受把 **明显诊断型** 的测试从默认 `test:pwsh:all` / `full` 门禁中移出，例如 `help.Tests.ps1` 里的性能对比路径，改由 `debug`、`Slow` 或单独 benchmark 命令承接？
  - 接受，但范围先收敛到 `Test-HelpSearchPerformance`，并明确改由 benchmark 入口承接。
- 是否接受把 host coverage 从默认 `pnpm test:pwsh:all` 中拆出，改为单独命令例如 `pnpm test:pwsh:coverage`？
  - 接受。实测基线显示，当前 `all` 外层墙钟约 `50.62s`；关闭 host coverage 后约 `37.72s`，收益约 `12.9s`，且 `Tests completed in` 基本不变，证明主要节省来自 coverage 收尾路径。

## Open Questions

- 暂无。

## Next Steps

-> 在你确认边界后，可进入 `/ce:plan`，把剩余热点按“共享热点优先、低风险噪音并行收口、诊断型测试是否分层”拆成实施清单。
