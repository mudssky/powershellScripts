---
title: fix: reduce remaining pwsh host test hotspots
type: fix
status: active
date: 2026-03-15
origin: docs/brainstorms/2026-03-15-pwsh-test-host-priority-brainstorm.md
---

# fix: reduce remaining pwsh host test hotspots

## Overview

这次计划聚焦在已经完成 `coverage` / `all` 语义收敛之后，继续压 PowerShell 测试剩余热点，但范围刻意收窄到“**不改默认门禁分层，优先把 host 测试压到 15s 左右**”。

当前基线来自用户最新一轮实测与仓库现状：

- 整体体感约 `38s`
- 测试阶段约 `23s`
- 最新慢测热点里最重的是：
  - `psutils/tests/cache.Tests.ps1`
    - host `6.59s`
    - linux `5.25s`
  - `tests/Invoke-Benchmark.Tests.ps1`
    - host `5.16s`
    - linux `3.87s`

这次计划完整承接 brainstorm 的关键结论：

1. 不重新设计 `pnpm test:pwsh:all` 的职责边界，继续保持当前完整门禁语义（see brainstorm: `docs/brainstorms/2026-03-15-pwsh-test-host-priority-brainstorm.md`）。
2. 如果两条目标不能一次同时达成，优先把 host 测试压到 `15s` 左右（see brainstorm: `docs/brainstorms/2026-03-15-pwsh-test-host-priority-brainstorm.md`）。
3. 允许修改生产代码增加测试 seam，但外部行为不能变化（see brainstorm: `docs/brainstorms/2026-03-15-pwsh-test-host-priority-brainstorm.md`）。
4. 采用“共享 seam + 保留 1 条真实 smoke”，优先处理 `cache.Tests.ps1` 与 `Invoke-Benchmark.Tests.ps1`（see brainstorm: `docs/brainstorms/2026-03-15-pwsh-test-host-priority-brainstorm.md`）。

## Problem Statement

前两轮优化已经把更大的结构性问题处理掉了：

- `pnpm test:pwsh:all` 已经不再默认承担 host coverage 收尾成本，当前语义固定为 host `test:pwsh:full:assertions` + Linux `test:pwsh:linux:full`（`package.json:25,46`）。
- `pnpm test:pwsh:coverage` 已经成为显式的 host coverage 入口，`pnpm test:pwsh:full` 仅作为兼容保留入口（`package.json:23-25`，`README.md:375-384`，`docs/local-cross-platform-testing.md:50-86`）。
- `help-search` benchmark 已经从默认 full 门禁中拆出，`Invoke-Benchmark` 默认日志噪音也已经做过一轮收口（`tests/Invoke-Benchmark.Tests.ps1:215-246`，`README.md:470-481`，`docs/plans/2026-03-15-001-fix-pwsh-test-hotspots-and-output-plan.md`）。

因此，当前剩余问题不再是“命令语义混乱”，而是两个非常具体的热点还在拖慢 host：

1. `tests/Invoke-Benchmark.Tests.ps1` 仍然有多条路径最终走到真实 benchmark 子进程执行；虽然已有 `PWSH_TEST_IN_PROCESS_BENCHMARK` 静音模式，但脚本末尾仍统一通过 `& $pwshPath -NoProfile -File $selected.Path @BenchmarkArgs` 拉起子进程（`scripts/pwsh/devops/Invoke-Benchmark.ps1:126-159,263-272`）。
2. `psutils/tests/cache.Tests.ps1` 覆盖面较广，涉及 `Invoke-WithCache`、`Clear-ExpiredCache`、`Get-CacheStats`、`Invoke-WithFileCache` 四类行为；对应模块实现也存在较多重复文件扫描、排序和时间判断（`psutils/modules/cache.psm1:114-180,220-289,396-605`）。

如果不继续深入这两个热点，后续再去抠大量亚秒级文件，收益会明显递减，很难把 host 从 `23s` 压到 `15s` 附近。

## Research Summary

### Found Brainstorm

找到匹配的 brainstorm：`docs/brainstorms/2026-03-15-pwsh-test-host-priority-brainstorm.md`。本计划将其作为主输入，并完整继承以下边界：

- 不重分层
- 优先 host `15s`
- 允许改生产代码加 seam
- 选择“共享 seam + 保留 1 条真实 smoke”
- 优先目标锁定 `cache.Tests.ps1` 与 `Invoke-Benchmark.Tests.ps1`

### Repo Research

- `package.json:23-25,38,46`
  - `test:pwsh:coverage` / `test:pwsh:full` / `test:pwsh:full:assertions` / `test:pwsh:all` 的语义已经清晰，不应在这轮再次调整。
- `PesterConfiguration.ps1:37-47,75,85-116`
  - 现在的 `qa` / `fast` / `full` / `coverage` 语义由环境变量驱动，执行集与 coverage 开关已经稳定；这轮重点不是重配 Pester，而是压热点。
- `tests/Invoke-Benchmark.Tests.ps1:3-106`
  - 测试已经有临时 benchmark 文件工厂、fake `fzf` 工厂、进程内静音环境变量和临时目录清理逻辑，说明当前已具备进一步下沉到 in-process 的基础。
- `tests/Invoke-Benchmark.Tests.ps1:110-246`
  - 现有断言包含显式名称执行、文本编号降级、`fzf` 路径、取消选择，以及 `help-search` benchmark smoke。也就是说，脚本契约覆盖已经较完整，提速空间主要在执行粒度。
- `scripts/pwsh/devops/Invoke-Benchmark.ps1:42-119`
  - benchmark 名称转换、catalog 发现、选择模块加载、交互选择都已经是独立函数，这轮最合理的 seam 不是另起新模块，而是继续把“选择/路由/执行”边界拆得更便于测试。
- `scripts/pwsh/devops/Invoke-Benchmark.ps1:126-272`
  - 当前脚本仍把“解析 catalog + 执行选中 benchmark”放在同一脚本流程里；若能把最终执行调用再包进 helper，就能让大部分测试避开真实子进程，只保留 1 条真实 smoke。
- `psutils/modules/cache.psm1:94-180`
  - `Clear-ExpiredCache` 依赖真实目录扫描、真实时间、`ShouldProcess`、`Write-Host` / `Write-Warning`。
- `psutils/modules/cache.psm1:220-289`
  - `Get-CacheStats` 目前每次都会重新扫描目录，并用两次排序计算 oldest/newest；如果测试里多次调用，这部分成本会被放大。
- `psutils/modules/cache.psm1:396-605`
  - `Invoke-WithCache` 与 `Invoke-WithFileCache` 仍散布多个 `Get-Date`、`Test-Path`、`Get-Item` 和文件写入点；这些都是引入 clock / filesystem seam 的候选位置。
- `psutils/tests/cache.Tests.ps1:99-426`
  - `Invoke-WithCache` 相关测试里已经大量 mock 掉 `Write-Host` / `Write-Warning`，说明当前瓶颈更像真实文件系统与重复调用成本，而不是控制台输出。
- `psutils/tests/cache.Tests.ps1:527-623`
  - `Get-CacheStats` 有多条测试分别独立调用 `Get-CacheStats`；这部分具备通过测试重组与模块微优化同时获益的空间。

### Institutional Learnings

最相关的既有结论如下：

1. `docs/solutions/workflow-issues/pwsh-cross-platform-test-workflow-stability-system-20260314.md:78-81,178-191`
   - 本地 coverage 责任与跨平台断言责任已经分开定义，不要在后续优化里重新把它们耦合回去。
2. `docs/plans/2026-03-15-001-fix-pwsh-test-hotspots-and-output-plan.md:131-225`
   - 前一轮已经明确：`Invoke-Benchmark.Tests.ps1` 要保留最小 CLI smoke，其余路径尽量下沉；`cache.Tests.ps1` 需要减少真实等待和文件系统成本。
3. `docs/plans/2026-03-15-002-refactor-separate-pwsh-coverage-gate-plan.md:87-88,315-346`
   - `Invoke-Benchmark` 的默认日志噪音已经基本收口，而 `cache.Tests.ps1` 仍是当前共享最慢文件。
4. `docs/solutions/developer-experience/benchmark-interactive-selection-psutils-20260314.md:59-61,117-130`
   - benchmark 入口已经沉淀了统一交互选择能力；后续不要把 `fzf` / 文本降级逻辑重新散落回脚本或测试里。
5. `todos/002-ready-p2-pwsh-test-followups.md:31-40,69-88,116-119`
   - 仓库已经明确记录过后续建议：`Invoke-Benchmark.Tests.ps1` 保留 1 条真实 smoke，其余下沉；coverage 补强更适合单独推进，不应继续夹在本轮热点提速里。

### External Research Decision

本议题完全围绕仓库内已有测试架构、Pester 运行方式、benchmark harness 与既有优化历史展开；本地上下文已经足够完整，因此本次 planning 跳过外部研究。

## SpecFlow Analysis

从开发者工作流与测试保护网角度，这次变更至少要覆盖以下 flow：

1. **提交前完整回归 flow**
   - 开发者运行 `pnpm test:pwsh:all`
   - host lane 继续走 `test:pwsh:full:assertions`
   - linux lane 继续走 `test:pwsh:linux:full`
   - 这次提速不能改变门禁命令、执行集或结果语义

2. **benchmark CLI flow**
   - 开发者运行 `pnpm benchmark -- help-search` 或未传名称时进入交互选择
   - 计划允许大部分路由测试下沉到进程内，但必须保留至少 1 条真实 CLI smoke
   - 否则真正的 benchmark 子进程回归会被延后到人工使用时才暴露

3. **cache public API flow**
   - `Invoke-WithCache`
   - `Clear-ExpiredCache`
   - `Get-CacheStats`
   - `Invoke-WithFileCache`
   - 这四个公开接口的外部行为都不能变，尤其是缓存命中/过期、`ShouldProcess` / `WhatIf`、文件格式和返回值结构

4. **状态清理 flow**
   - `tests/Invoke-Benchmark.Tests.ps1` 会创建临时 benchmark 脚本、fake `fzf`、marker 文件和 Unix 可执行文件
   - `psutils/tests/cache.Tests.ps1` 会修改缓存目录、文件时间戳和运行时统计状态
   - 任何 in-process 下沉都不能让这些状态穿透到后续测试

最重要的缺口与风险：

- **Gap 1:** 如果 `Invoke-Benchmark` 只保留显式 benchmark smoke，而把取消/选择/列表逻辑都改成 helper 测试，需要确保 helper 本身仍覆盖了脚本真正使用的路由分支。
- **Gap 2:** 如果 `cache` 模块只加 clock seam 不优化统计扫描，`Get-CacheStats` 相关测试可能仍然很重。
- **Gap 3:** 如果为了提速把 `WhatIf` 子进程 smoke 完全删掉，就会失去最难被 mock 正确表达的 `ShouldProcess` 保护栏。

这些 gap 会直接进入后文的实施阶段与验收标准。

## Proposed Solution

继续采用 brainstorm 已选中的主线：**在不改变默认门禁语义的前提下，为 `Invoke-Benchmark` 与 `cache` 增加轻量测试 seam，把大部分高成本断言改成进程内路径，同时各自保留 1 条最小真实 smoke。**

方案拆成三条实现线：

### 1. `Invoke-Benchmark`：把“选择/路由/执行”再拆细一层

- 保留现有 `ConvertTo-BenchmarkName`、`Get-BenchmarkCatalog`、`Select-BenchmarkCatalogItem` 等 helper，不重复发明新入口。
- 新增或显式化一层“解析目标 benchmark 并执行”的内部 helper，使测试可以在不拉起真实 benchmark 子进程的前提下验证：
  - 显式名称解析
  - catalog 缺失/未知 benchmark 错误
  - 取消选择
  - 参数透传
- `tests/Invoke-Benchmark.Tests.ps1` 只保留 1 条真实 CLI smoke，建议保留“显式 benchmark 名称 + 最小输出文件/marker 断言”这类路径，其余优先改为 in-process。

### 2. `cache`：同时做模块 seam 与测试重组

- 在 `psutils/modules/cache.psm1` 中增加轻量内部 seam，优先考虑：
  - 当前时间获取 helper
  - 缓存文件枚举 helper
  - oldest/newest 单次遍历或已枚举结果复用
  - 生成 `Get-CacheStats` 输出对象与主机输出的职责分离
- 在 `psutils/tests/cache.Tests.ps1` 中减少重复昂贵路径：
  - 能共享一次 `Get-CacheStats` 结果的断言，尽量放在同一 `It`
  - 过期语义继续靠时间戳回拨，而不是重新引入真实等待
  - `WhatIf` 继续保留 1 条子进程 smoke，不再扩散到其他断言
- 核心原则是“保语义、降成本”，不是删保护栏。

### 3. 范围约束：本轮不再混入 coverage 与门禁语义工作

- 不改 `package.json` 的 `test:pwsh:*` 命令职责
- 不动 `PesterConfiguration.ps1` 的 mode / coverage 开关语义
- 不把这轮重新扩展成 coverage 补强任务
- 不再把 `help-search` benchmark 或其他诊断型入口拉回默认 full

## Technical Approach

### Architecture

目标调用图如下：

```text
tests/Invoke-Benchmark.Tests.ps1
  -> in-process helper assertions
  -> 1 real CLI smoke

psutils/tests/cache.Tests.ps1
  -> deterministic file/time assertions
  -> 1 WhatIf child-process smoke
  -> fewer repeated stats scans

pnpm test:pwsh:all
  -> host full assertions
  -> linux full assertions
```

这次不会改 `pnpm test:pwsh:all` 本身，只会让这两类热点文件在当前门禁下变轻。

### Implementation Phases

#### Phase 1: Lock the exact baseline and write target

**Write scope**

- `docs/plans/2026-03-15-003-fix-reduce-remaining-pwsh-host-test-hotspots-plan.md`
- 实施时的性能记录文件或 solution 文档

**Tasks**

- 以当前用户提供的慢测清单作为计划基线。
- 实施前再记录一次 host 与 all 的 before 数据，至少保留：
  - `pnpm test:pwsh:slowest`
  - `pnpm test:pwsh:all:slowest`
- 把当前“测试阶段约 `23s`”作为 host 目标基线，把“整体约 `38s`”作为 stretch baseline。

**Success Criteria**

- 计划内所有性能目标都有明确 before 基线。
- 不会在实施中途把目标偷偷改成“只要快一点就行”。

#### Phase 2: Slim `Invoke-Benchmark` without losing CLI reality

**Write scope**

- `scripts/pwsh/devops/Invoke-Benchmark.ps1`
- `tests/Invoke-Benchmark.Tests.ps1`

**Tasks**

- 明确哪些断言必须保留真实 CLI smoke：
  - 至少 1 条显式 benchmark 名称执行路径
- 明确哪些断言可以下沉到 in-process：
  - catalog 发现
  - 选择/取消
  - 未知 benchmark 报错
  - 参数路由与返回 exit code
- 尽量让测试直接调用内部 helper，而不是每个 `It` 都再走一次真实 benchmark 子进程。
- 保持当前 `PWSH_TEST_IN_PROCESS_BENCHMARK` 的静音设计，不把低价值日志重新放回通过输出。

**Success Criteria**

- `tests/Invoke-Benchmark.Tests.ps1` 的 host 耗时相对当前 `5.16s` 有明显下降。
- 仍至少存在 1 条真实 CLI smoke。
- benchmark discoverability、交互选择、取消和显式名称执行都仍有测试保护。

#### Phase 3: Slim `cache` via seam + test regrouping

**Write scope**

- `psutils/modules/cache.psm1`
- `psutils/tests/cache.Tests.ps1`

**Tasks**

- 为 `cache` 模块引入最小必要的内部 seam：
  - clock seam
  - file enumeration seam
  - stats object construction seam
- 让 `Get-CacheStats` 尽量复用单次文件枚举结果，避免同一调用里多次排序或扫描。
- 重组 `cache.Tests.ps1`：
  - 合并可共享前置状态的 stats 断言
  - 保留 `WhatIf` 子进程 smoke，但不把子进程用到更多用例里
  - 继续用时间戳回拨表达过期逻辑
- 审查 `Clear-TestCache`、`BeforeEach` / `AfterAll` 清理，避免不必要的目录 churn。

**Success Criteria**

- `psutils/tests/cache.Tests.ps1` 的 host 耗时相对当前 `6.59s` 有明显下降。
- `Invoke-WithCache` / `Clear-ExpiredCache` / `Get-CacheStats` / `Invoke-WithFileCache` 的公开语义不变。
- `WhatIf`、cache hit/miss、过期、不同 cache type、stats 结构都仍被覆盖。

#### Phase 4: Verify total impact and document residual blockers

**Write scope**

- 可能新增的 `docs/solutions/**` 文档

**Tasks**

- 跑完整验证：
  - `pnpm qa`
  - `pnpm test:pwsh:all`
- 记录实施后的热点表，确认这两大热点是否都已下降。
- 如果 host 仍未到 `15s` 左右，必须补一张残余热点清单，不能只口头说“还有空间”。

**Success Criteria**

- 本轮结果能明确回答：
  - host 是否压到 `15s` 左右
  - `all` 是否继续随之下降
  - 剩余阻塞点是什么

## Alternative Approaches Considered

### Alternative A: 只改测试文件，不动生产代码

**Rejected because**

- `Invoke-Benchmark` 的主要成本就在真实子进程边界，不给脚本增加更易测的 helper，很难继续明显下降。
- `cache` 的主要成本来自模块实现与测试调用方式共同放大的文件系统成本，单靠 Pester 结构调整上限偏低。

### Alternative B: 更深的模块化重构

**Rejected because**

- 当前目标是继续压热点，不是重写 benchmark harness 或整个 cache 子系统。
- 会把这轮从“高收益收口”做成“结构重构”，超出用户当前期望。

### Alternative C: 重新分层默认门禁

**Rejected because**

- 与当前 brainstorm 的已确认约束冲突（see brainstorm: `docs/brainstorms/2026-03-15-pwsh-test-host-priority-brainstorm.md`）。
- 当前仓库已经完成 `coverage` / `all` 责任收敛，不应在这轮又改命令语义。

## System-Wide Impact

### Interaction Graph

- `pnpm test:pwsh:all`
  - 继续执行 host `test:pwsh:full:assertions`
  - 继续执行 Linux `test:pwsh:linux:full`
  - 但由于两个热点文件变轻，墙钟时间应继续下降
- `pnpm benchmark -- help-search`
  - 继续通过 `scripts/pwsh/devops/Invoke-Benchmark.ps1`
  - 这轮只改变测试 seam，不改变用户入口
- `Import-Module ./psutils/psutils.psd1`
  - `cache.psm1` 的公共函数与导出集合不应变化

### Error & Failure Propagation

- 如果 `Invoke-Benchmark` helper 与脚本主路径断裂，问题应先在 `tests/Invoke-Benchmark.Tests.ps1` 中暴露。
- 如果 `cache` seam 引入不慎，最容易破坏的是：
  - cache hit / miss 判断
  - `WhatIf` / `ShouldProcess`
  - `Get-CacheStats` 返回结构
  - `Invoke-WithFileCache` 的过期判断
- 这类失败必须由单测直接暴露，而不是等 `pnpm test:pwsh:all` 的慢测结果里间接出现。

### State Lifecycle Risks

- `tests/Invoke-Benchmark.Tests.ps1`
  - 需要继续正确清理临时 benchmark 脚本、fake `fzf` 与 marker 文件（`tests/Invoke-Benchmark.Tests.ps1:66-106`）。
- `psutils/tests/cache.Tests.ps1`
  - 需要继续隔离 `LOCALAPPDATA` / cache 目录 / runtime stats（`psutils/tests/cache.Tests.ps1:19-91`）。
- `cache` 模块若引入内部 seam，不能让测试可写状态泄露到模块导出 API。

### API Surface Parity

本轮预期应保持不变的外部接口：

- `pnpm test:pwsh:all`
- `pnpm test:pwsh:coverage`
- `pnpm benchmark`
- `Invoke-WithCache`
- `Clear-ExpiredCache`
- `Get-CacheStats`
- `Invoke-WithFileCache`

### Integration Test Scenarios

1. `pnpm test:pwsh:all` 继续通过，且 host / linux lane 结果语义不变。
2. `pnpm benchmark -- help-search` 继续可用，不因 helper 下沉而丢失真实执行能力。
3. `tests/Invoke-Benchmark.Tests.ps1` 仍能覆盖：
   - 显式 benchmark 名称
   - `fzf` 路径
   - 文本编号降级
   - 取消选择
4. `psutils/tests/cache.Tests.ps1` 仍能覆盖：
   - cache hit / miss
   - Force / NoCache
   - XML / Text cache
   - `WhatIf`
   - `Get-CacheStats`
   - `Invoke-WithFileCache`

## Acceptance Criteria

### Functional Requirements

- [x] `scripts/pwsh/devops/Invoke-Benchmark.ps1` 增加足够的内部 helper / seam，使大部分路由测试可在进程内完成。
- [x] `tests/Invoke-Benchmark.Tests.ps1` 仍保留至少 1 条真实 CLI smoke。
- [x] `tests/Invoke-Benchmark.Tests.ps1` 继续覆盖 benchmark 选择、取消、显式名称与参数路由。
- [x] `psutils/modules/cache.psm1` 增加最小必要的内部 seam，但不改变公开导出函数的外部行为。
- [x] `psutils/tests/cache.Tests.ps1` 继续覆盖 `Invoke-WithCache`、`Clear-ExpiredCache`、`Get-CacheStats`、`Invoke-WithFileCache` 的核心语义。
- [x] `WhatIf` / `ShouldProcess` 仍至少保留 1 条真实 smoke，不被完全替换成 mock。

### Non-Functional Requirements

- [ ] 同机基线下，host 测试阶段相对当前约 `23s` 明显下降，目标逼近 `15s`。
- [x] `tests/Invoke-Benchmark.Tests.ps1` 相对当前 host `5.16s` / linux `3.87s` 有明确下降。
- [x] `psutils/tests/cache.Tests.ps1` 相对当前 host `6.59s` / linux `5.25s` 有明确下降。
- [x] 默认通过日志不新增新的 benchmark / cache 噪音。
- [x] `pnpm test:pwsh:all` 在当前约 `38s` 基线上继续下降，即使本轮不保证一次压进 `20s`。

### Quality Gates

- [x] `pnpm qa`
- [x] `pnpm test:pwsh:all`
- [x] `pnpm test:pwsh:slowest`
- [x] `pnpm test:pwsh:all:slowest`
- [x] 记录一次 before / after 对比，至少覆盖 host 与 all 两套数据

## Success Metrics

- host 测试阶段从约 `23s` 压到接近 `15s`。
- `cache.Tests.ps1` 与 `Invoke-Benchmark.Tests.ps1` 不再合计占掉 host 热点的主导份额。
- 若 `all` 仍高于 `20s`，能够明确说明剩余最大的 1-2 个阻塞点是什么。

## Dependencies & Prerequisites

- 现有命令语义：
  - `package.json:23-25,38,46`
- 现有 Pester 配置：
  - `PesterConfiguration.ps1:37-116`
- benchmark 既有能力：
  - `scripts/pwsh/devops/Invoke-Benchmark.ps1:42-272`
  - `tests/Invoke-Benchmark.Tests.ps1:3-246`
- cache 既有能力：
  - `psutils/modules/cache.psm1:94-605`
  - `psutils/tests/cache.Tests.ps1:19-713`

## Risk Analysis & Mitigation

- **风险：helper seam 与真实脚本路径分叉。**
  - 缓解：保留至少 1 条真实 CLI smoke；helper 只承接可复用的路由与执行准备逻辑。

- **风险：为了提速削弱 `WhatIf` / `ShouldProcess` 保护栏。**
  - 缓解：保留 1 条真实子进程 smoke；其余测试再走更轻路径。

- **风险：`Get-CacheStats` 优化改变返回对象结构。**
  - 缓解：把结构断言保留在单测里，并优先重构内部实现而不是修改返回 shape。

- **风险：测试重组后状态泄露导致偶发失败。**
  - 缓解：审查 `BeforeEach` / `AfterEach` / `AfterAll` 清理，尤其是 PATH、临时工具目录、缓存目录和 runtime stats。

- **风险：本轮把 coverage 或门禁语义又带回范围。**
  - 缓解：明确把 coverage 补强与命令语义排除在本计划之外；如执行中发现相关问题，只登记为 follow-up。

## Documentation Plan

- 预期不需要修改 `README.md`、`docs/local-cross-platform-testing.md`、`CLAUDE.md` 或 OpenSpec，因为本轮不改变外部命令语义。
- 如实施后形成新的稳定结论，应补一篇 `docs/solutions/**`，记录：
  - 这次实际压掉了哪两个热点
  - 哪些 seam 有效
  - 哪些 residual blockers 还留着

## Validation Notes

- `tests/Invoke-Benchmark.Tests.ps1`
  - 当前单文件 host 断言路径约 `3.30s`
  - 在 `pnpm test:pwsh:all:slowest -- --top 5` 中：
    - host `1.68s`
    - linux `1.12s`
  - 对比用户给出的基线：
    - host `5.16s -> 1.68s`
    - linux `3.87s -> 1.12s`

- `psutils/tests/cache.Tests.ps1`
  - 当前单文件 host 断言路径约 `5.36s`
  - 在 `pnpm test:pwsh:all:slowest -- --top 5` 中：
    - host `5.59s`
    - linux `5.06s`
  - 对比用户给出的基线：
    - host `6.59s -> 5.59s`
    - linux `5.25s -> 5.06s`

- 次级热点的顺手收口
  - `psutils/tests/git.Tests.ps1`
    - 改为只导入 `git.psm1`，不再为两个纯模块测试整包导入 `psutils.psd1`
    - 单文件结果从约 `3.51s` 降到约 `1.25s`
    - 在 `pnpm test:pwsh:all` 中当前约 `308ms`
  - `psutils/tests/selection.Tests.ps1`
    - manifest 导出断言改为直接读取 `psutils.psd1`，不再整包导入模块
    - 单文件结果从约 `4.45s` 降到约 `2.34s`
    - 在 `pnpm test:pwsh:all` 中当前约 `764ms`
  - `psutils/tests/test.Tests.ps1`
    - 在 `test.psm1` 增加内部 `Invoke-ExecutableLookup` seam，只把真实 CLI smoke 留给最前面的存在/不存在断言
    - 缓存、NoCache 与跨平台安装检测相关场景改为在 `InModuleScope test` 中 mock 自有 helper，而不是继续真实扫 PATH
    - 单文件结果从约 `5.80s` 降到约 `3.78s`
    - 在 `pnpm test:pwsh:all` 中当前约 `1.17s`

- 门禁级结果
  - `pnpm qa` 通过
  - `pnpm test:pwsh:all` 通过
  - `pnpm test:pwsh:slowest -- --top 5` 通过
  - `pnpm test:pwsh:all:slowest -- --top 5` 通过
  - 最新 `pnpm test:pwsh:all`：
    - host `Tests completed in 24.43s`
    - linux `Tests completed in 19.98s`
  - 最新 `pnpm test:pwsh:slowest -- --top 8`：
    - host `Tests completed in 24.75s`

- 当前 residual blockers
  - `psutils/tests/cache.Tests.ps1` 仍是 host / linux 共享第一热点，当前 host 约 `5.06s`
  - host 下一梯队热点已转移到 `psutils/tests/filesystem.Tests.ps1`、`psutils/tests/hardware.Tests.ps1`、`tests/Invoke-Benchmark.Tests.ps1`、`tests/Sync-PathFromBash.Tests.ps1`
  - 当前同机 host `Tests completed in` 仍在 `24-25s` 一档，距离 `15s` 目标仍有明显差距，因此计划状态继续保留 `active`

## Sources & References

### Origin

- **Brainstorm document:** `docs/brainstorms/2026-03-15-pwsh-test-host-priority-brainstorm.md`
  - Carried-forward decisions:
    - 不重新分层默认门禁
    - 优先 host `15s`
    - 允许改生产代码加 seam
    - 采用“共享 seam + 保留 1 条真实 smoke”
    - 优先处理 `cache.Tests.ps1` 与 `Invoke-Benchmark.Tests.ps1`

### Internal References

- `package.json:23-25`
- `package.json:38`
- `package.json:46`
- `PesterConfiguration.ps1:37-47`
- `PesterConfiguration.ps1:75-116`
- `tests/Invoke-Benchmark.Tests.ps1:3-106`
- `tests/Invoke-Benchmark.Tests.ps1:110-246`
- `scripts/pwsh/devops/Invoke-Benchmark.ps1:42-119`
- `scripts/pwsh/devops/Invoke-Benchmark.ps1:126-272`
- `psutils/modules/cache.psm1:94-180`
- `psutils/modules/cache.psm1:220-289`
- `psutils/modules/cache.psm1:396-605`
- `psutils/tests/cache.Tests.ps1:19-91`
- `psutils/tests/cache.Tests.ps1:99-426`
- `psutils/tests/cache.Tests.ps1:527-713`
- `README.md:375-384`
- `docs/local-cross-platform-testing.md:50-86`

### Related Work

- `docs/plans/2026-03-15-001-fix-pwsh-test-hotspots-and-output-plan.md`
- `docs/plans/2026-03-15-002-refactor-separate-pwsh-coverage-gate-plan.md`
- `docs/solutions/workflow-issues/pwsh-cross-platform-test-workflow-stability-system-20260314.md`
- `docs/solutions/developer-experience/benchmark-interactive-selection-psutils-20260314.md`
- `todos/002-ready-p2-pwsh-test-followups.md`
