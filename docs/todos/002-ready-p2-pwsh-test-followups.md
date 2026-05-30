---
status: ready
priority: p2
issue_id: "002"
tags: [powershell, pester, benchmark, coverage, performance]
dependencies: []
---

# pwsh 测试热点与 coverage 后续收尾

## Problem Statement

当前 `pnpm test:pwsh:all` 已经恢复稳定并完成了一轮热点收口，但仍有两个值得继续跟进的点：

1. `tests/Invoke-Benchmark.Tests.ps1` 仍是默认 full 门禁中的显著热点之一。
2. host `pnpm test:pwsh:full` 的 coverage 仍停留在约 `51.96% / 75%`，与当前目标有明显差距。

这两个问题都不会阻断当前工作流使用，但会持续影响“排查性能回归的效率”和“coverage 质量门的可信度”。

## Findings

- 最新完整回归中：
  - host `tests/Invoke-Benchmark.Tests.ps1` 约 `8.92s`
  - linux `tests/Invoke-Benchmark.Tests.ps1` 约 `6.12s`
- 该测试文件已经在保留真实 CLI smoke 的前提下做过一轮收口，但子进程型断言仍占比较高。
- host `pnpm test:pwsh:full` 当前输出为 `Covered 51.96% / 75%. 3,114 analyzed Commands in 22 Files.`。
- 新增 `help-search` benchmark 之后，benchmark discoverability 已经有了基础设施，后续可以继续评估哪些 benchmark CLI 场景值得保留端到端、哪些适合进一步下沉到更轻的 helper 级测试。

## Proposed Solutions

### Option 1: 继续细拆 `Invoke-Benchmark.Tests.ps1`

**Approach:** 保留 1 条真实 CLI smoke，其余 catalog / 参数路由 / 输出文件断言继续下沉到更轻的 helper seam。

**Pros:**

- 对门禁墙钟时间最直接
- 不影响 benchmark 用户入口

**Cons:**

- 需要进一步重构 `scripts/pwsh/devops/Invoke-Benchmark.ps1`
- 若拆分边界不慎，容易损失 CLI 真实覆盖

**Effort:** 2-4 小时

**Risk:** Medium

---

### Option 2: 单独推进 coverage 补强

**Approach:** 选取当前 coverage 较低但价值高的模块，补充测试而不是继续排除统计对象。

**Pros:**

- 直接提升 `pester-coverage-50` 相关信号质量
- 不会牺牲既有行为覆盖

**Cons:**

- 需要先识别哪些模块最划算
- 不一定会立刻改善 `test:pwsh:all` 墙钟时间

**Effort:** 4-8 小时

**Risk:** Low

---

### Option 3: 组合推进

**Approach:** 先小幅压 `Invoke-Benchmark.Tests.ps1`，同时补一批低成本 coverage。

**Pros:**

- 同时改善性能与 coverage
- 能把后续收尾一次做完

**Cons:**

- 作用域更大
- 更适合单独开一轮 work，而不是夹在小修里顺手做

**Effort:** 1 天

**Risk:** Medium

## Recommended Action

建议分两步做：

1. 先处理 `Invoke-Benchmark.Tests.ps1`，目标是保留 1 条真实 CLI smoke，其余能下沉的逻辑尽量下沉。
2. 再单独跑一次 coverage 分析，按模块收益排序补测试，避免盲目撒网。

## Technical Details

**Affected files:**

- `tests/Invoke-Benchmark.Tests.ps1`
- `scripts/pwsh/devops/Invoke-Benchmark.ps1`
- `tests/benchmarks/*.Benchmark.ps1`
- `PesterConfiguration.ps1`
- `psutils/tests/**/*.Tests.ps1`

**Related components:**

- `pnpm benchmark -- help-search`
- `pnpm test:pwsh:full`
- `pnpm test:pwsh:all`

**Database changes (if any):**

- 无

## Resources

- `docs/solutions/workflow-issues/pwsh-help-benchmark-and-log-noise-system-20260315.md`
- `docs/plans/2026-03-15-001-fix-pwsh-test-hotspots-and-output-plan.md`
- `tests/Invoke-Benchmark.Tests.ps1`
- `scripts/pwsh/devops/Invoke-Benchmark.ps1`

## Acceptance Criteria

- [ ] 明确 `Invoke-Benchmark.Tests.ps1` 里哪些场景必须保留真实 CLI smoke，哪些可以继续下沉。
- [ ] `Invoke-Benchmark.Tests.ps1` 的 host / linux 耗时进一步下降，且 benchmark CLI 真实覆盖未丢失。
- [ ] 对 host coverage 低于目标的模块形成一份按收益排序的补测清单。
- [ ] 补测后 host coverage 相对当前基线有明确提升。

## Work Log

### 2026-03-15 - 初始登记

**By:** Codex

**Actions:**

- 根据本轮完整回归结果，记录 `Invoke-Benchmark.Tests.ps1` 热点与 host coverage 未达标两项后续工作。
- 结合已完成的 benchmark 分层与日志去噪结果，整理后续候选方案与推荐顺序。

**Learnings:**

- benchmark discoverability 已经成型，后续再压 CLI 测试时不需要重新设计入口。
- coverage 问题更适合做一次单独分析，而不是继续夹在性能收口里顺手处理。

## Notes

- 当前工作流已经可用，这份 todo 记录的是“下一轮值得继续做的收尾项”，不是阻断问题。
