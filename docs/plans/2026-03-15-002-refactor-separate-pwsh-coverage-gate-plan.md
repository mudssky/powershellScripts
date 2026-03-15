---
title: refactor: Separate pwsh coverage gate from cross-platform all
type: refactor
status: active
date: 2026-03-15
origin: docs/brainstorms/2026-03-15-pwsh-test-log-optimization-brainstorm.md
---

# refactor: Separate pwsh coverage gate from cross-platform all

## Overview

这次计划的目标是把 `pnpm test:pwsh:all` 重新收敛成“默认提交前跨环境功能断言门禁”，不再让 host coverage 留在默认关键路径里，同时新增显式 coverage 入口 `pnpm test:pwsh:coverage`。在此基础上，继续处理共享热点测试和默认通过日志中的残余噪音。

这不是单纯新增一个脚本名，而是把当前已经半显式存在的职责边界彻底拉直：

- `qa` 继续是快速质量门，不承担完整 pwsh 回归。
- `test:pwsh:all` 继续是 pwsh 相关改动的提交前跨环境门禁。
- coverage 变成显式、可单独运行、可单独度量、可单独写入规范的验证入口。

基于 2026-03-15 的同机实测，当前 `pnpm test:pwsh:all` 外层墙钟约 `50.62s`；仅关闭 host coverage 后下降到 `37.72s`，节省约 `12.9s`。两组运行的 `host Tests completed in` 基本不变，因此这次优化的最大收益点明确来自 coverage 收尾路径，而不是测试文件本体（see brainstorm: `docs/brainstorms/2026-03-15-pwsh-test-log-optimization-brainstorm.md`）。

## Problem Statement / Motivation

当前工作流存在四个耦合问题：

1. `pnpm test:pwsh:all` 同时承担跨环境断言和 host coverage，导致默认外层墙钟被 host coverage 收尾放大。
2. 文档已经说明 Linux `full` 不承担 coverage，但 coverage 仍然隐式绑定在 host `full` / `all` 上，职责边界不够显式。
3. 默认 full 日志里仍混入 benchmark CLI 文案、`WhatIf` 主机提示与少量 warning，影响通过时的可读性。
4. 剩余热点已经从第一轮大热点转移到 `tests/Invoke-Benchmark.Tests.ps1`、`psutils/tests/cache.Tests.ps1` 等共享热点，后续优化需要和命令职责拆分一起考虑，而不是分裂成两套独立工作。
5. coverage 门槛本身存在口径漂移：OpenSpec 当前写的是 `>=50%`，而最近控制台输出显示的是 `/ 75%` 门槛；如果不在本次计划里一起澄清，新增 `test:pwsh:coverage` 也只是在搬运混乱。

这次计划需要解决的核心不是“让某一条命令更快一点”，而是把 **命令职责、coverage 责任、默认日志信号和共享热点治理** 放回一致的系统语义里。

## Proposed Solution

### 1. 明确三条命令的最终职责

- `pnpm test:pwsh:full`
  - 继续保留为当前 host coverage-enabled full 路径，作为兼容入口。
  - 继续作为 Docker 不可用时的最小 fallback 验证入口。
  - 本次计划不直接打破它现有“带 coverage”的公开语义，避免与现有 README / CLAUDE / OpenSpec 正面冲突。

- `pnpm test:pwsh:coverage`
  - Host 平台 coverage-enabled 验证入口。
  - 负责承接覆盖率门槛、coverage 相关规范和显式的 coverage 采样需求。
  - 作为 `openspec/specs/pester-coverage-50/spec.md` 对应的 documented coverage-enabled command。
  - 在迁移期内允许与 `pnpm test:pwsh:full` 等价，作为更清晰的公开命令名。

- `pnpm test:pwsh:<host-assertions-only>`
  - 新增 host 无 coverage 的完整断言路径。
  - 只服务于 `pnpm test:pwsh:all` 及与提交前门禁等价的派生命令。
  - 该入口可以是公开命令，也可以是内部 helper；但其语义必须在实现和文档里被明确描述。

- `pnpm test:pwsh:all`
  - 并发执行 `pnpm test:pwsh:<host-assertions-only>` + `pnpm test:pwsh:linux:full`。
  - 继续承担提交前跨环境完整断言门禁。
  - 默认不再输出 host coverage 收尾结果。

### 1.1 明确开发者、fallback 与 CI 的新契约

- **本地日常 / 提交前**
  - `pnpm test:pwsh:all` 仍是 pwsh 相关改动的默认提交前动作。
  - `pnpm test:pwsh:coverage` 是显式 coverage 验证入口，不再隐含在 `all` 里。
  - `pnpm test:pwsh:full` 在迁移期内保留为兼容覆盖率入口，但文档主名字应切到 `coverage`。

- **Docker 不可用**
  - `pnpm test:pwsh:full` 继续是最小 fallback，且在迁移期内仍保留现有 coverage 语义。
  - 文档必须明确：Linux 断言依赖 CI / WSL。
  - 如果最终协作规则不再要求每次本地 pre-commit 都跑 coverage，则需明确说明 coverage 由 CI 和显式 `pnpm test:pwsh:coverage` 承担。

- **CI / PR**
  - CI 需要拥有一条显式 coverage gate，而不是继续依赖“默认 full 恰好带 coverage”的旧语义。
  - 规范层将 coverage threshold 绑定到一条 canonical host command；本计划建议使用 Windows host 的 `pnpm test:pwsh:coverage` 作为规范平台，避免 `windowsOnly` 过滤导致覆盖率口径漂移。

### 2. 继续保持既有语义，不退化门禁

- 不把 `test:pwsh:all` 改成 `fast` 组合。
- 不移除真实 Linux 容器路径。
- 不把诊断 benchmark 重新塞回默认 full。
- 不为了提速而削弱失败退出码、artifact 隔离或双路结果可见性。

### 3. 在 coverage 拆分后继续收口剩余热点与噪音

优先级沿用 brainstorm 的结论：

- 第一优先级：`tests/Invoke-Benchmark.Tests.ps1`
- 第二优先级：`psutils/tests/cache.Tests.ps1`
- 并行低风险收口：`psutils/tests/env.Tests.ps1`、`psutils/tests/web.Tests.ps1`
- 继续保持 `Test-HelpSearchPerformance` 留在 benchmark 入口，不回流到默认 full（see brainstorm: `docs/brainstorms/2026-03-15-pwsh-test-log-optimization-brainstorm.md`）

## Technical Approach

### Phase 1: Split the coverage gate

#### `package.json`

以 `package.json` 为命令语义主入口，重排 root PowerShell 测试命令：

```json
{
  "scripts": {
    "test:pwsh:full": "<existing host full with coverage>",
    "test:pwsh:coverage": "<explicit documented coverage command>",
    "test:pwsh:<host-assertions-only>": "<host full assertions without coverage>",
    "test:pwsh:linux:full": "<linux full assertions without coverage>",
    "test:pwsh:all": "pnpm exec concurrently ... \"pnpm test:pwsh:<host-assertions-only>\" \"pnpm test:pwsh:linux:full\""
  }
}
```

实施原则：

- 优先复用现有 `PWSH_TEST_ENABLE_COVERAGE` 环境变量，而不是复制一套新的 Pester 配置分支。
- 尽量保持 `PesterConfiguration.ps1` 仍是唯一 coverage 开关来源。
- 不直接打破 `test:pwsh:full` 的兼容语义；优先新增一个 assertions-only lane 供 `all` 使用。
- `pnpm test:pwsh:coverage` 可以在迁移期内代理到当前 `pnpm test:pwsh:full`，但文档主名字和规范口径应切到 `coverage`。
- 在命令迁移同时，必须澄清 coverage threshold 的 source of truth，以及控制台输出门槛与 OpenSpec 门槛为何不一致。

#### `PesterConfiguration.ps1`

- 保持 `PWSH_TEST_ENABLE_COVERAGE` 的显式覆盖能力作为唯一 truth source。
- 不额外引入新的 mode 名称去表达 coverage。
- 确保 `full` 和 `coverage` 的差异只体现在 coverage 开关，而不是偷偷分叉测试集合。

#### CI / workflow 对齐

当前 `.github/workflows/test.yml` 直接运行 `Invoke-Pester -Configuration (./PesterConfiguration.ps1)`，没有经过 `package.json` 的命令语义层。这意味着：

- 如果本地文档改成“`test:pwsh:coverage` 才是 documented coverage command”，CI 不能继续隐式漂移。
- 需要明确决定 CI 是继续保留“矩阵里直接跑默认 full 配置”，还是改为显式调用新的 coverage 命令 / host full 命令。
- 计划要求至少完成一次 CI 工作流审计，避免本地和 CI 对 `full` / `coverage` 的理解长期分叉。
- 建议终态：
  - cross-platform matrix 继续承担 assertions
  - coverage gate 收敛到单独的一条 canonical host lane

### Phase 2: Keep the shared-hotspot cleanup on the same branch

coverage 拆分不是终点；它只负责拿掉当前最大、最确定的外层成本。拆分后仍需按共享热点继续推进：

- `tests/Invoke-Benchmark.Tests.ps1`
  - 目标是继续减少重复子进程拉起与默认 `Write-Host` 噪音。
  - 保留一条最小 CLI smoke。
  - 其余 catalog / 选择 / 参数路由尽量继续下沉到同进程测试或更安静的 seam。

- `psutils/tests/cache.Tests.ps1`
  - 目标是进一步减少真实等待、无必要文件系统 churn 和默认日志外泄。
  - 时间相关断言优先回拨状态或时间戳，而不是继续等待真实时间。

- `tests/Sync-PathFromBash.Tests.ps1`
  - 继续保持把多条 `WhatIf` 路径合并到单个子进程中验证。
  - 默认 full 日志中不应再出现额外的 `WhatIf` 主机提示残留。

- `psutils/tests/env.Tests.ps1` 与 `psutils/tests/web.Tests.ps1`
  - 收口低价值 warning。
  - 保留失败与关键 warning，避免为了“安静”把真实信号抹掉。

### Phase 3: Update every command-facing document together

这次语义变化不能只改 `package.json`，必须同批更新以下接口层：

- `README.md`
- `docs/local-cross-platform-testing.md`
- `CLAUDE.md`
- `AGENTS.md`
- `.github/workflows/test.yml` 中与本地命令语义有关的说明或调用
- `openspec/specs/pester-coverage-50/spec.md`
- `openspec/specs/local-cross-platform-pester-testing/spec.md`
- `openspec/specs/pester-test-performance/spec.md`

更新原则：

- 不让任何文档继续暗示 “`test:pwsh:all` 默认含 coverage”。
- 不让任何规范继续把 coverage 门槛绑定到旧的 host `full` 命令。
- Docker fallback 说明必须继续成立。
- `qa` 与 `test:pwsh:all` 的职责边界必须保持不变。

## Alternative Approaches Considered

### Alternative A: 只改日志展示，不改 coverage 责任

拒绝原因：

- 只能让输出“看起来更安静”，对外层墙钟几乎没有决定性改善。
- 无法解释为什么 `all` 明明是功能门禁，却默认承担 coverage 收尾。

### Alternative B: 保持 `test:pwsh:full` 继续含 coverage，只给 `all` 偷偷加内部 no-coverage helper

仅可作为短期迁移策略，不应作为长期终态。

拒绝作为终态的原因：

- 会让显式命令和真实职责继续错位。
- 会让 `test:pwsh:coverage` 变成“只是 `full` 的另一个名字”，而不是独立语义。
- 新加入的开发者仍然很难直观看懂哪条命令负责 coverage。

### Alternative C: 从 `all` 里移除 Linux 或退化成 `fast`

拒绝原因：

- 直接破坏 `test:pwsh:all` 的跨环境门禁定位。
- 与前序 brainstorm / solution / 文档约定冲突。

## System-Wide Impact

### Interaction Graph

实施后的目标调用链：

1. `pnpm test:pwsh:all`
   - `concurrently`
   - `pnpm test:pwsh:<host-assertions-only>`
   - `pnpm test:pwsh:linux:full`

2. `pnpm test:pwsh:coverage`
   - `pnpm test:pwsh:full` 或等价 host coverage-enabled 路径
   - coverage 收尾与门槛判断

3. `pnpm test:pwsh:all:slowest`
   - `scripts/pester-duration-report.mjs`
   - 继续从控制台摘要行提取文件级耗时
   - 不能因为命令重排而丢失 `[host]` / `[linux]` lane 或 `"[+] file duration (...)"` 结构

4. `pnpm test:pwsh:detailed`
   - 需要明确它跟随 coverage-enabled host path 还是新增 dedicated coverage-detailed lane
   - 不能在文档中继续模糊地写成“详细版 full”，却不说明是否含 coverage

### Error & Failure Propagation

- `pnpm test:pwsh:full`
  - 在迁移期内继续保留当前 coverage-enabled 语义。
  - 因此它仍可能在断言失败、coverage 收尾失败或 coverage 门槛不达标时返回非零。
- `pnpm test:pwsh:coverage`
  - 在断言失败、coverage 收尾失败或 coverage 门槛不达标时返回非零。
- `pnpm test:pwsh:<host-assertions-only>`
  - 只在断言失败或 host harness 失败时返回非零。
- `pnpm test:pwsh:linux:full`
  - 继续只在 Linux 容器 full 断言或容器执行失败时返回非零。
- `pnpm test:pwsh:all`
  - 任一路失败即整体失败。
  - 但仍需保留双路最终结论与标签化输出。

### State Lifecycle Risks

- Host 结果文件仍默认写入 `testResults.xml`。
- Linux 容器结果仍写入 `testResults-linux.xml` 对应的 volume 输出。
- `test:pwsh:coverage` 若沿用 `testResults.xml`，必须确认不会让使用者误以为 `all` 同样默认产出 coverage artifact。
- 如需单独区分 coverage artifact，必须同步更新文档与 report 使用路径。

### API Surface Parity

以下接口必须同步保持一致：

- `package.json`
- `PesterConfiguration.ps1`
- `docker-compose.pester.yml`
- `.github/workflows/test.yml`
- `.vscode/tasks.json`
- `README.md`
- `docs/local-cross-platform-testing.md`
- `CLAUDE.md`
- `AGENTS.md`
- `openspec/specs/pester-coverage-50/spec.md`
- `openspec/specs/local-cross-platform-pester-testing/spec.md`
- `openspec/specs/pester-test-performance/spec.md`

### Integration Test Scenarios

1. 开发者执行 `pnpm test:pwsh:full`
   - 期望：在迁移期内仍保持当前 coverage-enabled 行为。
   - 期望：不会因为本次拆分被静默改成 assertions-only。

2. 开发者执行 `pnpm test:pwsh:coverage`
   - 期望：host 完整断言 + coverage 一起执行。
   - 期望：coverage 门槛不达标时返回非零。

3. 开发者执行 `pnpm test:pwsh:all`
   - 期望：继续并发执行 host full 与 Linux full。
   - 期望：host lane 实际走的是 assertions-only path，而不是当前 coverage-enabled `test:pwsh:full`。
   - 期望：总体外层墙钟明显低于当前 `50.62s` 基线。

4. 开发者执行 `pnpm test:pwsh:all:slowest`
   - 期望：仍能正确提取 host / linux 双 lane 的文件级耗时。

5. 开发者触发 benchmark 相关测试
   - 期望：默认 full 日志中不再刷出不必要的 `Running benchmark:` / `Script:` 文案。
   - 期望：真正的 benchmark 诊断仍通过 `pnpm benchmark -- help-search` 等入口显式执行。

6. Docker 不可用时
   - 期望：文档仍明确 `pnpm test:pwsh:full` 是最小 fallback。
   - 期望：不会让团队误以为 fallback 已自动覆盖 coverage。
   - 期望：当改动直接影响 coverage 语义时，文档能明确提醒额外运行 `pnpm test:pwsh:coverage` 或依赖 CI。

7. CI 运行 Pester 工作流时
   - 期望：CI 对 coverage 的语义与本地文档一致。
   - 期望：不会继续默认依赖一个已经在本地语义上“去 coverage 化”的命令。

8. 开发者执行 `pnpm test:pwsh:detailed` / `pnpm test:pwsh:all:slowest`
   - 期望：派生命令都能明确说明自己跟随的是 assertion path、coverage path，还是新的显式 coverage 入口。

## Acceptance Criteria

- [x] `package.json` 新增 `pnpm test:pwsh:coverage`，并让 `pnpm test:pwsh:all` 默认不再承担 host coverage。
- [x] `package.json` 新增一个 host assertions-only lane 供 `pnpm test:pwsh:all` 使用，且不直接打破 `pnpm test:pwsh:full` 当前 coverage-enabled 兼容语义。
- [x] `PesterConfiguration.ps1` 继续以 `PWSH_TEST_ENABLE_COVERAGE` 作为 coverage 唯一开关来源，不引入新的配置分叉。
- [x] `pnpm test:pwsh:all` 继续保持 `host full + linux full` 并发门禁，不退化为 `fast` 组合，也不移除真实 Linux 容器路径。
- [x] `pnpm test:pwsh:coverage` 成为文档和 OpenSpec 中唯一明确指向 coverage 门槛的命令入口。
- [x] coverage threshold 的 source of truth 已被澄清，`openspec/specs/pester-coverage-50/spec.md` 中的规范值与实际命令输出口径不再漂移。
- [x] coverage threshold 的 canonical 平台和 CI 执行位置已明确，避免 `windowsOnly` 过滤造成不同 host 口径漂移；计划默认以 Windows host `pnpm test:pwsh:coverage` 作为规范口径。
- [x] `.github/workflows/test.yml` 已完成审计，并与新的本地命令语义保持一致，避免 CI / 本地对 coverage 的理解漂移。
- [x] `.vscode/tasks.json` 已完成审计，避免编辑器默认任务继续静默走旧的 coverage 语义。
- [x] `README.md`、`docs/local-cross-platform-testing.md`、`CLAUDE.md`、`AGENTS.md`、相关 OpenSpec 全部同步更新，不再有“`all` 默认含 coverage”的旧叙述。
- [x] `scripts/pester-duration-report.mjs` 与 `Show-PesterDurationReport.ps1` 仍能基于控制台摘要行正确产出慢文件报告。
- [x] `pnpm test:pwsh:detailed`、`pnpm test:pwsh:slowest`、`pnpm test:pwsh:all:slowest` 等派生命令在新语义下都有明确归属，不继续默认绑定旧的 coverage-enabled `full`。
- [x] `tests/Invoke-Benchmark.Tests.ps1` 的默认通过日志噪音继续下降，且不牺牲最小 CLI smoke。
- [ ] `psutils/tests/cache.Tests.ps1`、`tests/Sync-PathFromBash.Tests.ps1`、`psutils/tests/env.Tests.ps1`、`psutils/tests/web.Tests.ps1` 的残余噪音或结构性成本至少收口一轮。
- [x] `pnpm qa` 继续通过，`qa:pwsh` 的快速质量门职责不被破坏。

## Success Metrics

- 在同一台机器上，`pnpm test:pwsh:all` 外层墙钟相对 `50.62s` 基线下降至少 `10s`，目标收敛到 `40s` 内。
- 在同一台机器上，coverage 拆分后 `pnpm test:pwsh:all` 的 `host Tests completed in` 不因命令重排而显著变差。
- `pnpm test:pwsh:coverage` 能稳定提供 coverage 门槛验证，不要求开发者再通过 `all` 间接观察 coverage。
- 默认 `all` / `full` 通过日志中的 benchmark 文案、`WhatIf` 主机提示和低价值 warning 数量继续下降。
- `20s` 以内仍作为 host full 内层 `Tests completed in` 的后续优化目标；若本次实施结束后仍未达到，需要附带新的热点表和阻塞说明，而不是口头延后。

## Dependencies & Prerequisites

- 现有 `PWSH_TEST_ENABLE_COVERAGE` 环境变量覆盖能力（`PesterConfiguration.ps1`）
- 现有 `concurrently` 聚合模式与 `[host]` / `[linux]` 标签输出
- 现有 Linux 容器 harness：`docker-compose.pester.yml`
- 现有慢文件报告入口：`scripts/pester-duration-report.mjs`
- 现有 benchmark / full 职责边界文档与前序 solution

## Validation Notes

- 2026-03-15 当前实现验证：
  - `pnpm test:pwsh:coverage` 通过，最新输出为 `Covered 52.54% / 50%. 3,114 analyzed Commands in 22 Files.`，coverage 口径已与 OpenSpec 的 `50%` 要求对齐。
  - `pnpm test:pwsh:all` 通过；当前命令链改为 `host pnpm test:pwsh:full:assertions + linux pnpm test:pwsh:linux:full`，外层墙钟约 `38s`，相较 brainstorm 中的 `50.62s` 基线下降约 `12s+`。
  - `pnpm test:pwsh:slowest -- --top 3` 与 `pnpm test:pwsh:all:slowest -- --top 3` 均通过，说明新的 coverage / all 语义下慢文件报告仍可正常解析。
  - `pnpm qa` 通过，`qa:pwsh` 未因命令拆分受到破坏。
  - `tests/Invoke-Benchmark.Tests.ps1` 在默认 `full` / `all` 日志中的 `Running benchmark`、`Script:` 与取消 warning 文案已收回测试内静音路径，不再污染通过日志。

- 当前剩余空间：
  - `psutils/tests/cache.Tests.ps1` 仍是 host / linux 共享最慢文件。
  - `psutils/tests/env.Tests.ps1`、`psutils/tests/web.Tests.ps1` 与 `tests/Sync-PathFromBash.Tests.ps1` 还有进一步收口默认噪音和结构性成本的空间，因此 plan 维持 `active`。

## Risk Analysis & Mitigation

- **风险：`test:pwsh:full` 语义变化让已有使用者误以为 coverage 还在默认 full 里。**
  - 缓解：本计划不直接打破 `test:pwsh:full` 的兼容语义；优先通过新增 assertions-only lane 让 `all` 变轻。

- **风险：`test:pwsh:coverage` 只是换名，没有真正成为唯一 coverage 门槛入口。**
  - 缓解：把 `openspec/specs/pester-coverage-50/spec.md` 与文档都绑定到新命令，移除旧表述。

- **风险：coverage threshold 本身继续漂移，导致新命令只是换名不换标准。**
  - 缓解：在实施阶段同时核对 OpenSpec、Pester 实际输出与任何隐式默认阈值，明确唯一 source of truth。

- **风险：为了压日志而误隐藏真实失败信号。**
  - 缓解：只收口用户展示型 `Write-Host`、重复 `WhatIf` 与预期 warning；失败详情与关键 warning 必须保留。

- **风险：CI 继续直接调用 `Invoke-Pester`，导致本地与 CI 语义分叉。**
  - 缓解：把 `.github/workflows/test.yml` 纳入必审范围；要么显式改用新命令，要么在文档中说明 CI 的独立职责并保持一致。

- **风险：coverage artifact 或 test result path 发生误解。**
  - 缓解：保留 artifact isolation 说明；如调整 output path，则同步更新 report 流程和文档。

- **风险：热点优化过度依赖 mock，削弱真实 CLI 语义。**
  - 缓解：每个热点文件至少保留一条最小真实 smoke，其余路径再下沉到同进程测试。

## Documentation Plan

- `README.md`
  - 更新 `full`、`coverage`、`all` 的职责说明。
  - 明确 `coverage` 是主文档名字，`full` 为兼容入口。
  - 明确 benchmark 仍不属于默认 full / all 门禁。

- `docs/local-cross-platform-testing.md`
  - 更新命令表，让 coverage 从 `all` 中显式拆出。
  - 明确 host fallback 仍走 `full`，以及何时需要额外显式运行 `coverage`。

- `CLAUDE.md`
  - 更新 root PowerShell 测试工作流说明与环境变量约定。

- `AGENTS.md`
  - 保持“pwsh 改动提交前执行 `pnpm test:pwsh:all`”不变。
  - 如需补充 coverage 显式入口，必须写清它不是 `all` 的替代物，以及 coverage 是否仍属于本地必跑动作。

- `.github/workflows/test.yml`
  - 审核并决定是否改为显式调用新命令，或补充注释说明 CI 责任。
  - 明确 coverage gate 的 canonical lane。

- `.vscode/tasks.json`
  - 审核编辑器默认测试任务是否需要切到新命令，或显式注明它仍走哪条语义路径。

- `openspec/specs/pester-coverage-50/spec.md`
  - 明确 coverage target 绑定到 `pnpm test:pwsh:coverage`。
  - 明确规范口径对应的 host 平台。

- `openspec/specs/local-cross-platform-pester-testing/spec.md`
  - 更新 `full` / `all` / fallback 的语义。

- `openspec/specs/pester-test-performance/spec.md`
  - 更新默认门禁的性能目标与日志噪音边界。

- `docs/solutions/`
  - 实施完成后补一篇 solution，沉淀 coverage 拆分后的 before/after 数据与残余热点。

## Sources & References

### Origin

- **Brainstorm document:** `docs/brainstorms/2026-03-15-pwsh-test-log-optimization-brainstorm.md`
  - Carried-forward decisions:
    - `test:pwsh:all` 继续保留跨环境门禁定位，不退化为 `fast`
    - host coverage 从默认 `all` 关键路径中拆出，改由单独命令承担
    - `Test-HelpSearchPerformance` 继续留在 benchmark 入口，不回到默认 full
    - 后续优化优先打双平台共享热点，而不是只盯单平台热点
    - `WhatIf` / benchmark / warning 噪音要从测试边界上收口，而不是靠流重定向掩盖

### Internal References

- `package.json:23-42`
  - 现有 `test:pwsh:*` 命令图与 `all` 聚合方式
- `PesterConfiguration.ps1:37-57`
  - 现有 `PWSH_TEST_MODE` / `PWSH_TEST_ENABLE_COVERAGE` 逻辑
- `PesterConfiguration.ps1:106-121`
  - coverage 配置与排除模块
- `docker-compose.pester.yml:42-55`
  - Linux `full` 已显式关闭 coverage
- `README.md:358-367`
  - 当前 `all` / `full` / Docker fallback 说明
- `README.md:415-463`
  - `qa` 与 `all` 的职责边界，以及 benchmark 不属于默认门禁
- `docs/local-cross-platform-testing.md:57-80`
  - 当前命令矩阵与 benchmark 工作流说明
- `docs/local-cross-platform-testing.md:92-126`
  - 平台 coverage 说明与 Docker 不可用 fallback
- `CLAUDE.md:141-168`
  - 当前 root PowerShell 测试工作流与 coverage 环境变量约定
- `.github/workflows/test.yml:19-45`
  - 当前 CI 直接调用 `Invoke-Pester`
- `.vscode/tasks.json`
  - 当前编辑器任务也绕过 `pnpm test:pwsh:*`
- `scripts/pester-duration-report.mjs:77-113`
  - 当前慢文件报告对控制台摘要行的解析依赖
- `tests/Invoke-Benchmark.Tests.ps1:110-253`
  - benchmark CLI 契约测试仍是默认日志噪音与共享热点来源之一
- `docs/solutions/workflow-issues/pwsh-test-command-alignment-system-20260314.md:141-171`
  - `qa` / `all` 边界与提交前动作约定
- `docs/solutions/workflow-issues/pwsh-cross-platform-test-workflow-stability-system-20260314.md:177-196`
  - Host coverage / Linux full 责任分层的前序结论
- `docs/solutions/workflow-issues/pwsh-help-benchmark-and-log-noise-system-20260315.md:183-216`
  - 当前热点治理与降噪原则

### Research Notes

- 本次 planning 未额外引入外部研究。
- 原因：仓库已有最近 48 小时内的 brainstorm、plan、solution、README、CLAUDE 与 OpenSpec 足够覆盖当前问题空间，且用户已明确给出目标边界与实测验证方向。
