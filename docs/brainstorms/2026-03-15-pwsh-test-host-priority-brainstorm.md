---
date: 2026-03-15
topic: pwsh-test-host-priority
---

# PowerShell 测试热点继续收口，优先压 host 到 15s 左右

## What We're Building
这次要收敛的是 2026-03-15 当前这轮 PowerShell 测试继续提速的目标边界，而不是重新讨论测试命令该怎么分层。

现状是：前两轮优化之后，用户体感总耗时约 `38s`，其中测试阶段约 `23s`；最新慢测清单里最明显的共享热点仍然是：

- `psutils/tests/cache.Tests.ps1`
  - host `6.59s`
  - linux `5.25s`
- `tests/Invoke-Benchmark.Tests.ps1`
  - host `5.16s`
  - linux `3.87s`

用户希望继续往下压，理想目标是整体进入 `20s` 内，或者至少把 host 测试压到 `15s` 左右。经过本轮澄清后，优先级已经明确：如果两条线不能一次同时打满，先保 host `15s` 左右这条硬线，同时尽量带动 `pnpm test:pwsh:all` 继续下降。

## Why This Approach
当前约束已经把方案空间收得很窄：

- 不接受重新分层，`pnpm test:pwsh:all` 继续保持现在这条完整门禁语义。
- 允许修改生产代码或模块，只要外部行为不变；这意味着可以为测试加 seam，而不是只能在 Pester 文件里“挤牙膏式”压时间。
- 用户已经明确选择了“共享 seam + 保留 1 条真实 smoke”这条路线，而不是只做测试层微调。

在这个前提下，最高收益的点很集中：

- `Invoke-Benchmark.Tests.ps1` 的显著成本主要来自重复拉起真实 `pwsh -NoProfile -File` 子进程；如果不抽 helper，单靠 Pester 技巧很难继续大幅下降。
- `cache.Tests.ps1` 的显著成本主要来自真实文件系统副作用、时间判断与重复清理；如果不在 `cache.psm1` 里增加更可测的边界，也很难继续压。
- 这两个文件合计已经占 host 热点的核心份额，优先处理它们，比再去抠大量亚秒级文件更接近目标。

换句话说，这次不是“再普遍优化一点”，而是聚焦两个共享热点，用生产代码层面的轻量 seam 换取更便宜的测试执行路径。

## Approaches Considered

### Approach 1: 共享 seam + 保留 1 条真实 smoke
改 `scripts/pwsh/devops/Invoke-Benchmark.ps1` 和 `psutils/modules/cache.psm1`，把目录发现、参数路由、时间判断、文件副作用这类高频逻辑拆成可在进程内测试的 helper；`tests/Invoke-Benchmark.Tests.ps1` 保留 1 条真实 CLI smoke，其余优先改成 in-process；`cache.Tests.ps1` 保留真实语义，但减少不必要的真实等待和重复 IO。

**Pros:**
- 最有机会同时打掉 host 侧两个最大热点。
- 不改 `all/full` 的门禁边界。
- 真实 CLI 和真实缓存语义仍保留最小 smoke，不会把风险全推给 mock。

**Cons:**
- 需要改生产代码。
- 需要更仔细地守住外部行为不变。

**Best when:** 不改门禁语义，但要优先冲 host `15s`。

### Approach 2: 只改测试文件，不动生产代码
主要通过 `BeforeAll` 复用、合并重复断言、减少临时目录和子进程调用次数来提速。

**Pros:**
- 改动面最小。
- 回归风险最低。

**Cons:**
- 提速上限偏低。
- 很难真正解决 `Invoke-Benchmark` 子进程成本和 `cache` 文件系统成本。

**Best when:** 只想拿一轮保守的小收益。

### Approach 3: 更深的测试友好型重构
进一步模块化 benchmark 调度和 cache 生命周期，引入更明确的 clock / IO seam，让大部分测试转成纯函数或轻量集成。

**Pros:**
- 长期最干净。
- 后续再压时间会更容易。

**Cons:**
- 范围最大。
- 这一轮容易做重。

**Best when:** 接受一轮更完整的结构性重构。

## Recommendation
推荐 **Approach 1: 共享 seam + 保留 1 条真实 smoke**。

理由很直接：

- 这是在“不重分层”前提下，仍然最可能把 host 测试往 `15s` 压近的路线。
- 它直接命中当前最贵的两个共享热点，而不是在边缘文件上做低收益优化。
- 它还能顺带改善 `pnpm test:pwsh:all`，因为 `cache` 和 `Invoke-Benchmark` 都是双平台热点。
- 相比更深的模块化重构，这条路线的改动面更可控，符合“先打最大热点”的 YAGNI 原则。

## Key Decisions
- `pnpm test:pwsh:all` 的默认完整门禁语义保持不变，不通过重新分层来换时间。
- 本轮优先级是 host 测试先压到 `15s` 左右；整体 `20s` 视为本轮尽量逼近的 stretch target，而不是先于 host 目标的硬门槛。
- 允许改生产代码，只要外部行为不变；因此可以在 `Invoke-Benchmark.ps1` 和 `cache.psm1` 中引入测试友好的 seam 或 helper。
- `Invoke-Benchmark.Tests.ps1` 应保留 1 条真实 CLI smoke，其余 catalog / 参数路由 / 选择逻辑优先下沉到 in-process 路径。
- `cache.Tests.ps1` 应继续保留真实缓存语义验证，但要减少重复文件系统成本、真实等待和不必要的清理路径。
- 本轮优化顺序应先打 `cache.Tests.ps1` 与 `Invoke-Benchmark.Tests.ps1`，再决定是否继续追后面的亚秒级文件。

## Resolved Questions
- 是否接受重新分层默认门禁？
  - 不接受，`test:pwsh:all` 继续保留当前完整门禁语义。
- 如果两条目标不能一次同时达成，先保哪条？
  - 先保 host 测试压到 `15s` 左右。
- 是否允许为提速修改生产脚本/模块并加入 seam？
  - 允许，只要外部行为不变。
- 在几个候选路线中选哪条？
  - 选择 `Approach 1: 共享 seam + 保留 1 条真实 smoke`。

## Open Questions
- 暂无。

## Next Steps
-> `/ce:plan`，把 `Invoke-Benchmark` 与 `cache` 的 seam 设计、测试下沉范围、验证命令和回归基线拆成可执行计划。
