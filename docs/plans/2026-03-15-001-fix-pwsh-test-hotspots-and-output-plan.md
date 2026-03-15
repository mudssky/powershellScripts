---
title: fix: optimize remaining pwsh test hotspots and output
type: fix
status: completed
date: 2026-03-15
origin: docs/brainstorms/2026-03-15-pwsh-test-log-optimization-brainstorm.md
---

# fix: optimize remaining pwsh test hotspots and output

## Overview

本计划聚焦 `pnpm test:pwsh:all` 在上一轮稳定性修复之后留下的“第二梯队”问题：少数共享热点仍然拉高总时长，默认通过日志里仍混入 `WhatIf`、`WARNING:` 与诊断型 `Write-Host` 输出（see brainstorm: `docs/brainstorms/2026-03-15-pwsh-test-log-optimization-brainstorm.md`）。

本计划完整承接该 brainstorm 的关键决策：

1. 保持 `test:pwsh:all` 继续作为 `host full + linux full` 的提交门禁，不退回 `fast` / smoke 组合。
2. 下一轮优化优先级从“只看 host 热点”切换为“优先打双平台共享热点”，因为当前墙钟时间已经被较慢的一路锁死。
3. `Test-HelpSearchPerformance` 不再留在默认 `test:pwsh:full` / `test:pwsh:all` 门禁中，改由 benchmark 入口承接。
4. `Invoke-Benchmark.Tests.ps1`、`cache.Tests.ps1`、`Sync-PathFromBash` 相关测试继续保留在 full 验证体系内，但要减少重复子进程、真实等待和默认控制台噪音。
5. 默认 full 日志中的 `WhatIf` 残余不再继续靠流重定向修补，而是通过测试边界重构解决（see brainstorm: `docs/brainstorms/2026-03-15-pwsh-test-log-optimization-brainstorm.md`）。

这是一份增量收尾计划，不重写 2026-03-14 已经完成的跨平台稳定性基线；重点是把剩余热点、诊断型测试分层和默认输出收口做干净。

## Problem Statement

最新 `test.log` 已经把“剩余问题”具体化，而不是抽象的“还有点慢”：

- host `Tests completed in 39.05s`
- linux `Tests completed in 40.4s`

当前 `pnpm test:pwsh:all` 的真实体感时间几乎完全由最慢的一路决定，因此继续只优化 Windows 专属热点，收益会明显递减。

基于最新日志的剩余热点：

- `psutils/tests/help.Tests.ps1`
  - host 约 `5.04s`
  - linux 约 `18.1s`
  - 其中 `Test-HelpSearchPerformance` 会在 full 门禁内真实执行“自定义解析 vs Get-Help”性能对比，更像诊断/benchmark，而不是功能正确性断言
- `tests/Invoke-Benchmark.Tests.ps1`
  - host 约 `8.33s`
  - linux 约 `5.65s`
  - 主要成本来自每个 `It` 都重新拉起一次 `pwsh -NoProfile -File`
- `psutils/tests/cache.Tests.ps1`
  - host 约 `5.48s`
  - linux 约 `5.11s`
  - 表明真实等待、文件系统副作用和缓存路径操作仍是共享热点

默认输出的剩余噪音也有明确来源：

- `32` 行 `What if:`，绝大多数来自 `Sync-PathFromBash` 的缓存目录和 PATH 预演
- `3` 条 `WARNING:`，来源集中在 `env.Tests.ps1` 与 `web.Tests.ps1`

本地实验已经确认一个关键约束：`WhatIf` 主机提示不能靠 `6>$null`、`$WarningPreference='SilentlyContinue'` 或 `$InformationPreference='SilentlyContinue'` 消除。因此剩余 `WhatIf` 噪音不是“重定向还没写够”，而是测试设计本身需要收口。

## Research Summary

### Repo Research

- `package.json:23,32,38,40,50`
  - root 命令已经明确分层为 `test:pwsh:full`、`test:pwsh:linux:full`、`test:pwsh:all`、`benchmark`、`qa:benchmark`。
  - 这轮不应该发明新的门禁命令，而应在现有入口内做收尾优化。
- `psutils/tests/help.Tests.ps1:17,316`
  - `help.Tests.ps1` 既包含功能正确性断言，也包含 `Test-HelpSearchPerformance` 这种性能对比型测试。
- `psutils/modules/help.psm1:66,996,1040`
  - `Test-HelpSearchPerformance` 仍由模块导出，适合作为 benchmark 入口复用的底层能力，而不是继续混在默认 full 测试里。
- `tests/Invoke-Benchmark.Tests.ps1:4,63`
  - 当前测试通过真实子进程覆盖 CLI 路径，验证价值高，但粒度偏重。
- `scripts/pwsh/devops/Invoke-Benchmark.ps1:54,81,104,132,146`
  - benchmark 目录自动发现、交互选择与显式 benchmark 名称执行已经具备基础设施。
  - 当前 `tests/benchmarks/` 下只有 `CommandDiscovery.Benchmark.ps1`，还没有 help search 对应的 benchmark 脚本。
- `psutils/tests/env.Tests.ps1:150,179,222` 与 `tests/Sync-PathFromBash.Tests.ps1:3,36`
  - 仍有直接调用 `-WhatIf` 的测试路径，这些路径会把主机提示带进默认 full 日志。
- `psutils/tests/web.Tests.ps1:28`
  - 只在部分上下文中 mock 了 `Write-Warning`，这解释了为什么 full 日志里仍会看到 icon 下载失败 warning。
- `README.md:347,356,359,445`、`docs/local-cross-platform-testing.md:21,34,46,61`
  - 文档已明确：`test:pwsh:all` 是提交前跨环境完整验证；`benchmark` / `qa:benchmark` 是独立诊断入口。
  - 这为把诊断型性能比较从 full 下沉到 benchmark 提供了现成语义容器。

### Institutional Learnings

最相关的已有内部结论：

1. `docs/plans/2026-03-14-006-fix-stabilize-pwsh-cross-platform-test-workflow-plan.md`
   - 已固定 `test:pwsh:all` 的 full 语义与 Host coverage / Linux assertion 分工。
   - 本次只能在该语义内部继续收尾，不能回退为 `fast`。
2. `docs/solutions/workflow-issues/pwsh-cross-platform-test-gate-performance-stability-system-20260315.md`
   - 第一批热点已经被压下去，当前进入第二梯队收尾阶段。
   - “默认输出只保留断言相关信息；诊断输出走 verbose/debug” 已成为仓库内生方向。
3. `docs/solutions/workflow-issues/pwsh-cross-platform-test-workflow-stability-system-20260314.md`
   - 诊断价值依赖完整 host / linux 结果，不能用“换轻一点的命令”伪装提速。
4. `docs/solutions/performance-issues/command-discovery-regression-profile-20260314.md`
   - 高成本命令探测必须优先替换为轻量 seam，不能在热点路径里无约束使用真实发现逻辑。
5. `docs/solutions/developer-experience/benchmark-interactive-selection-psutils-20260314.md`
   - benchmark 入口应复用统一 catalog / selection 基础设施，而不是为单个场景再造一条平行命令。

### External Research Decision

本议题完全围绕仓库现有测试工作流、PowerShell 模块、benchmark harness 与 OpenSpec 约束，且本地上下文已经足够完整，因此本次规划跳过外部研究。

## SpecFlow Analysis

从用户流和失败定位链路看，本次变更必须覆盖以下 spec-flow 风险点：

1. **从 full 移出诊断型测试后，仍需保留功能正确性断言。**
   - `help.Tests.ps1` 不能因为移走性能对比就削弱 `Search-ModuleHelp`、`UseGetHelp`、`Find-PSUtilsFunction`、`Get-FunctionHelp` 的常规功能验证。
2. **benchmark 入口必须成为明确替代，而不是“移走后无人运行”。**
   - 需要新增可 discover 的 benchmark 脚本，并确保 `pnpm benchmark -- <name>` 可直接执行。
3. **默认输出收口不能削弱失败诊断。**
   - 噪音可以下沉，但失败详情、文件级进度摘要与最终汇总必须保留。
4. **`WhatIf` 相关测试重构后，仍要证明 ShouldProcess 行为没有被破坏。**
   - 需要从“断言主机提示文本”转向“断言对象结果 / 副作用 / mock seam”。
5. **benchmark CLI 测试瘦身后，仍要保留至少一条真实端到端 smoke。**
   - 否则会把 benchmark 命令的真实回归全部留给人工使用后才暴露。

这些点已纳入下面的技术方案与验收标准。

## Proposed Solution

继续采用 brainstorm 确认后的主线：**保持 full 语义不变，优先打共享热点，并把 `Test-HelpSearchPerformance` 明确迁移到 benchmark。**

方案拆为四条实现线：

### 1. 把 help performance 对比从 full 门禁移到 benchmark

- 保留 `help.Tests.ps1` 中所有功能正确性断言。
- 移除默认 full 对 `Test-HelpSearchPerformance` 的依赖。
- 新增独立 benchmark 脚本，例如 `tests/benchmarks/HelpSearch.Benchmark.ps1`，由 `pnpm benchmark -- help-search` 承接性能对比场景。
- 如有必要，保留 `Test-HelpSearchPerformance` 作为 benchmark 复用的内部/导出能力，但不再由 full 测试直接触发。

### 2. 缩小 `Invoke-Benchmark.Tests.ps1` 的重复子进程成本

- 保留至少一条真实 `pwsh -NoProfile -File` 端到端 smoke。
- 把 catalog、选择、参数路由等纯逻辑验证尽量转为 in-process helper 级测试，或通过更轻的脚本 seam 复用。
- 必要时将 `scripts/pwsh/devops/Invoke-Benchmark.ps1` 中适合单测的 helper 保持纯函数化，降低每个 `It` 重拉子进程的需求。

### 3. 继续压缩 `cache` / `WhatIf` / warning 的默认噪音

- `cache.Tests.ps1`：优先减少真实时间等待与重复清理输出。
- `env.Tests.ps1` / `tests/Sync-PathFromBash.Tests.ps1`：避免在默认 full 路径中直接断言 `-WhatIf` 主机提示，改为更可控的 seam。
- `web.Tests.ps1`：把 icon 下载失败这类预期 fallback warning 收口到测试边界，避免穿透到 full 通过日志。
- `profile` 相关测试与脚本：若默认 full 日志中仍保留无关性能打印，则仅在测试态或 debug 态下沉，不影响真实交互式 profile 的用户可见行为。

### 4. 同步 benchmark / full 的职责文档与规范

- 文档要清楚表达：
  - `test:pwsh:all` 继续承担提交前完整验证
  - `benchmark` 承担诊断/性能比较
  - 不再把性能对比型测试混入默认 full 结果
- 如 OpenSpec 中对 full 性能语义或 benchmark 语义已有约束，需要同步修正，避免“代码事实已经变了，规范还停留在旧边界”。

## Technical Approach

### Architecture

本次不新增新的测试域命令，继续复用现有调用图：

```text
pnpm test:pwsh:all
  -> concurrently(host, linux)
    -> pnpm test:pwsh:full
    -> pnpm test:pwsh:linux:full

pnpm benchmark -- <name>
  -> scripts/pwsh/devops/Invoke-Benchmark.ps1
    -> tests/benchmarks/*.Benchmark.ps1
```

变化将集中在两个边界：

1. **Pester full 边界**
   - 去掉诊断型性能比较
   - 保留功能正确性与跨平台断言
2. **benchmark 边界**
   - 接住从 full 迁出的性能对比
   - 保持 discoverable、可显式调用、可单独测

### Implementation Phases

#### Phase 1: Migrate help performance comparison to benchmark

**Write scope**

- `psutils/tests/help.Tests.ps1`
- `psutils/modules/help.psm1`
- `tests/benchmarks/HelpSearch.Benchmark.ps1`
- `scripts/pwsh/devops/Invoke-Benchmark.ps1`（如 benchmark 参数路由需要微调）
- `tests/Invoke-Benchmark.Tests.ps1`（补充新 benchmark 的 smoke）

**Tasks**

- 在 `help.Tests.ps1` 中移除默认 full 对 `Test-HelpSearchPerformance` 的直接断言，同时保留其余功能断言。
- 新增 `tests/benchmarks/HelpSearch.Benchmark.ps1`：
  - 输入 `SearchTerm`
  - 复用 `Search-ModuleHelp` / `Test-HelpSearchPerformance` 能力
  - 输出可读的对比结果
- 若 benchmark 需要更稳定的函数入口，整理 `help.psm1` 导出边界或提取纯辅助函数。
- 在 `tests/Invoke-Benchmark.Tests.ps1` 中为 `help-search` 新增至少一条显式 benchmark 名称 smoke。

**Success Criteria**

- `pnpm test:pwsh:all` 不再执行 `Test-HelpSearchPerformance`。
- `pnpm benchmark -- help-search` 可以稳定运行。
- `help.Tests.ps1` 保留搜索功能、`UseGetHelp`、`IncludeScripts`、`Find-PSUtilsFunction`、`Get-FunctionHelp` 的覆盖。

#### Phase 2: Reduce remaining shared hotspots without weakening coverage

**Write scope**

- `tests/Invoke-Benchmark.Tests.ps1`
- `scripts/pwsh/devops/Invoke-Benchmark.ps1`
- `psutils/tests/cache.Tests.ps1`
- 可能涉及 `psutils/modules/cache.psm1`（如需要时间 seam）

**Tasks**

- 评估 `Invoke-Benchmark` 哪些行为必须通过真实子进程验证，哪些可转为 in-process helper 测试。
- 保留一条真实 CLI 端到端路径，避免 benchmark 命令完全失去 smoke coverage。
- 为 `cache` 路径引入更便于单测的时间/seam，尽量替代 `Start-Sleep` 式真实等待。
- 避免为了提速而移除 `cache` 的真实缓存命中/过期语义验证；目标是降低实现成本，不是删断言。

**Success Criteria**

- `tests/Invoke-Benchmark.Tests.ps1` 不再是 host / linux 共享热点前二。
- `psutils/tests/cache.Tests.ps1` 在 host / linux 上的耗时较当前基线明显下降。
- `pnpm test:pwsh:all` 继续覆盖 benchmark CLI 的最小真实 smoke。

#### Phase 3: Remove default full noise at the test boundary

**Write scope**

- `tests/Sync-PathFromBash.Tests.ps1`
- `psutils/tests/env.Tests.ps1`
- `psutils/tests/web.Tests.ps1`
- `profile/profile.ps1` 或 `psutils/tests/profile_windows.Tests.ps1`（仅在确有必要时）

**Tasks**

- 把 `Sync-PathFromBash` 相关测试从“直接依赖 `-WhatIf` 主机提示”转成“断言返回对象、路径集合、预期调用 seam”。
- 对预期 fallback warning 场景统一 mock 或收口，避免通过日志出现 `WARNING: Could not download icon ...` 这类已知噪音。
- 若 profile 加载耗时打印仍影响 full 可读性，仅在测试态 / debug 态抑制，不改变真实交互用户默认体验。

**Success Criteria**

- 默认 full 通过日志中不再出现成批 `What if:` 提示。
- 预期 fallback warning 在默认通过日志中显著减少，仅保留真正需要开发者关注的 warning。
- `debug` / `detailed` 路径仍能看到完整诊断输出。

#### Phase 4: Update docs, specs, and verification baselines

**Write scope**

- `README.md`
- `docs/local-cross-platform-testing.md`
- `CLAUDE.md`（如 benchmark / full 职责说明需要补充）
- `openspec/specs/pester-test-performance/spec.md`
- 视实际语义变化决定是否更新：
  - `openspec/specs/local-cross-platform-pester-testing/spec.md`
  - `openspec/specs/pester-coverage-50/spec.md`
- `docs/solutions/workflow-issues/` 新增实施后 solution

**Tasks**

- 文档中增加 `help-search` benchmark 的 discoverability。
- 明确“诊断型性能比较走 benchmark，提交前完整验证走 full / all”的职责边界。
- 若 OpenSpec 中需要正式声明“full 默认不混入诊断型 benchmark 测试”，同步修正规范。
- 记录 before / after 数据，沉淀成新的 solution，避免后续回归再从头分析。

**Success Criteria**

- 文档、实现与 OpenSpec 对 full / benchmark 分工描述一致。
- 新同学仅阅读 README / local testing doc，也能知道如何运行 `help-search` benchmark。
- 实施完成后有新的 solution 记录本轮收尾结论与基线数据。

## Alternative Approaches Considered

### Alternative A: 保留 `Test-HelpSearchPerformance` 在 full，只做日志静音

**Rejected because**

- 这不能消除 Linux `help.Tests.ps1` 的 `18.1s` 主热点。
- 该测试本质是性能比较，继续放在 full 里会让门禁耗时受诊断型任务支配。

### Alternative B: 继续用重定向 / preference 变量压 `WhatIf`

**Rejected because**

- 本地验证已经证明 `WhatIf` 主机提示不会被 `6>$null`、`$WarningPreference` 或 `$InformationPreference` 吃掉。
- 继续堆重定向只会制造脆弱补丁，不会真正改变默认 full 输出。

### Alternative C: 直接把 `test:pwsh:all` 降级为更轻的组合

**Rejected because**

- 与 `docs/brainstorms/2026-03-15-pwsh-test-log-optimization-brainstorm.md` 的已确认决策冲突。
- 会破坏 `qa` 与 `all` 的职责边界，并与前一轮稳定性方案打架。

## System-Wide Impact

### Interaction Graph

- `pnpm test:pwsh:all`
  - 继续触发 host full 与 linux full
  - 但 `help.Tests.ps1` 不再调用性能比较路径
- `pnpm benchmark -- help-search`
  - 通过 `scripts/pwsh/devops/Invoke-Benchmark.ps1`
  - 发现 `tests/benchmarks/HelpSearch.Benchmark.ps1`
  - 复用 `help.psm1` 中的搜索/对比能力
- `tests/Invoke-Benchmark.Tests.ps1`
  - 同时约束 benchmark discoverability 与 CLI smoke

### Error & Failure Propagation

- 如果 benchmark 脚本新增后 discoverability 断裂，问题应在 `Invoke-Benchmark.Tests.ps1` 中首先暴露，而不是等用户手动运行 benchmark 才发现。
- 如果 `help.Tests.ps1` 误删了功能断言，`pnpm test:pwsh:all` 应该仍然通过功能测试直接红，而不是让 benchmark 成为唯一保护网。
- 如果 `WhatIf` 测试重构过度，可能出现“日志变安静了，但 ShouldProcess 语义未被验证”。因此必须保留返回对象 / side-effect seam 的断言。

### State Lifecycle Risks

- `Invoke-Benchmark.Tests.ps1` 会创建临时 benchmark 脚本、fake `fzf` 可执行文件和 marker 文件；测试瘦身时必须避免临时目录清理遗漏。
- `cache.Tests.ps1` 会修改测试缓存目录、文件时间戳和 runtime cache state；引入时间 seam 后要确保不会污染其他测试。
- `Sync-PathFromBash` 相关测试会操作 `PATH` 与测试缓存目录；必须继续保证 BeforeEach / AfterEach 清理完整。

### API Surface Parity

- 需要同步审视的接口与入口：
  - `pnpm test:pwsh:full`
  - `pnpm test:pwsh:linux:full`
  - `pnpm test:pwsh:all`
  - `pnpm benchmark -- help-search`
  - `pnpm qa:benchmark`
- 文档接口：
  - `README.md`
  - `docs/local-cross-platform-testing.md`
  - `CLAUDE.md`

### Integration Test Scenarios

- `pnpm test:pwsh:all` 在默认 full 下通过，且日志中不再出现批量 `WhatIf` 噪音。
- `pnpm benchmark -- help-search` 能从新 benchmark 脚本成功运行并输出性能比较。
- `pnpm test:pwsh:full` 继续覆盖 help 搜索功能正确性，而不依赖 benchmark 才发现功能回归。
- `pnpm test:pwsh:all` 中 benchmark CLI 的最小 smoke 仍被覆盖，避免 catalog / selection / route 断裂。

## Acceptance Criteria

### Functional Requirements

- [x] `psutils/tests/help.Tests.ps1` 不再在默认 full 中执行 `Test-HelpSearchPerformance`。
- [x] 新增 `tests/benchmarks/HelpSearch.Benchmark.ps1`，并能通过 `pnpm benchmark -- help-search` 运行。
- [x] `tests/Invoke-Benchmark.Tests.ps1` 继续覆盖 benchmark CLI 的最小真实 smoke。
- [x] `help` 模块的功能性搜索断言在 full 路径中保持完整。
- [x] `Sync-PathFromBash` / `env` / `web` 相关测试在默认 full 下不再把预期噪音直接刷到控制台。

### Non-Functional Requirements

- [x] `pnpm test:pwsh:all` 在同一台本地机器上的墙钟时间相对当前 `test.log` 基线（host `39.05s` / linux `40.4s`）有明确下降。
- [x] 默认 full 日志保留文件级进度、失败详情和最终汇总，但显著减少 `WhatIf` 与预期 fallback warning。
- [x] `debug` / `detailed` 路径不失去诊断信息。

### Quality Gates

- [x] `pnpm qa`
- [x] `pnpm test:pwsh:all`
- [x] `pnpm benchmark -- help-search`
- [x] 至少记录一次 before / after 对比，覆盖 host / linux 热点变化

## Success Metrics

- `help.Tests.ps1` 不再成为 `pnpm test:pwsh:all` 的第一热点来源。
- `tests/Invoke-Benchmark.Tests.ps1` 与 `psutils/tests/cache.Tests.ps1` 至少有一个退出共享热点前二。
- 默认通过日志中的 `WhatIf` 行数较当前基线显著减少，理想目标是归零或接近归零。
- `pnpm test:pwsh:all` 的总体墙钟时间进入低 30 秒区间或更好；若环境波动较大，也至少应相对当前基线有可重复的两位数百分比下降。

## Dependencies & Prerequisites

- 现有 benchmark harness：`scripts/pwsh/devops/Invoke-Benchmark.ps1`
- benchmark 目录约定：`tests/benchmarks/*.Benchmark.ps1`
- 当前 cross-platform full 基线：
  - Host coverage 责任在 `test:pwsh:full`
  - Linux full 断言责任在 `test:pwsh:linux:full`
- OpenSpec 中关于 full / coverage / cross-platform 的现有约束：
  - `openspec/specs/pester-test-performance/spec.md:10`
  - `openspec/specs/local-cross-platform-pester-testing/spec.md:14`
  - `openspec/specs/pester-coverage-50/spec.md:3`

## Risk Analysis & Mitigation

- **风险：把性能对比从 full 移走后，help 搜索性能回归不再自动暴露。**
  - 缓解：新增 discoverable benchmark，并在文档中明确入口；必要时后续接入专门 benchmark workflow，而不是塞回 full。

- **风险：`Invoke-Benchmark` 测试瘦身后，真实 CLI 路径被覆盖不足。**
  - 缓解：保留至少一条真实 `pwsh -NoProfile -File` 端到端 smoke，再把其余逻辑测试下沉为轻量单测。

- **风险：为了去噪把 `ShouldProcess` 语义一起删掉。**
  - 缓解：改断言目标，不改语义目标；继续验证返回对象、路径集合、mock seam 与副作用空操作行为。

- **风险：profile 输出收口误伤真实交互式体验。**
  - 缓解：仅在测试态 / debug 路径增加抑制开关，不改变普通交互 shell 的默认行为。

## Documentation Plan

- `README.md`
  - 增加 `help-search` benchmark 的使用方式与定位说明。
- `docs/local-cross-platform-testing.md`
  - 明确 full 门禁与 benchmark 诊断的职责边界。
- `CLAUDE.md`
  - 如需要，补充“性能比较类入口走 benchmark，而不是 full”的说明。
- `openspec/specs/pester-test-performance/spec.md`
  - 如果需要正式声明“full 默认不承载诊断型 benchmark 比较”，在这里更新规范。
- `openspec/specs/local-cross-platform-pester-testing/spec.md`
  - 仅当 full / benchmark 的职责边界影响本地 cross-platform 文档语义时更新。
- `openspec/specs/pester-coverage-50/spec.md`
  - 预期本轮不改 coverage 责任；若实现中出现边界变化再同步修正。
- `docs/solutions/workflow-issues/`
  - 新增实施后 solution，记录剩余热点收尾与 benchmark 分层的最终结论。

## Sources & References

### Origin

- **Brainstorm document:** `docs/brainstorms/2026-03-15-pwsh-test-log-optimization-brainstorm.md`
  - Carried-forward decisions:
    - 保持 `test:pwsh:all` 的 full 语义
    - 优先打双平台共享热点
    - `Test-HelpSearchPerformance` 下沉到 benchmark
    - `WhatIf` 噪音通过测试边界重构解决，而不是继续堆重定向

### Internal References

- `package.json:23,32,38,40,50`
- `psutils/tests/help.Tests.ps1:17,316`
- `psutils/modules/help.psm1:66,996,1040`
- `tests/Invoke-Benchmark.Tests.ps1:4,63`
- `scripts/pwsh/devops/Invoke-Benchmark.ps1:54,81,104,132,146`
- `psutils/tests/env.Tests.ps1:150,179,222`
- `tests/Sync-PathFromBash.Tests.ps1:3,36`
- `psutils/tests/web.Tests.ps1:28`
- `README.md:347,356,359,445`
- `docs/local-cross-platform-testing.md:21,34,46,61`
- `openspec/specs/pester-test-performance/spec.md:10`
- `openspec/specs/local-cross-platform-pester-testing/spec.md:14`
- `openspec/specs/pester-coverage-50/spec.md:3`

### Related Work

- `docs/plans/2026-03-14-006-fix-stabilize-pwsh-cross-platform-test-workflow-plan.md`
- `docs/solutions/workflow-issues/pwsh-cross-platform-test-gate-performance-stability-system-20260315.md`
- `docs/solutions/workflow-issues/pwsh-cross-platform-test-workflow-stability-system-20260314.md`
- `docs/solutions/performance-issues/command-discovery-regression-profile-20260314.md`
- `docs/solutions/developer-experience/benchmark-interactive-selection-psutils-20260314.md`
