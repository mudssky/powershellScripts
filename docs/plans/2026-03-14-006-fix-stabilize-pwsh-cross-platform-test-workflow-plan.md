---
title: fix: stabilize pwsh cross-platform test workflow
type: fix
status: active
date: 2026-03-14
origin: docs/brainstorms/2026-03-14-pwsh-test-optimization-brainstorm.md
---

# fix: stabilize pwsh cross-platform test workflow

## Overview

本计划聚焦修复并优化当前的 PowerShell 跨平台测试工作流，使 `pnpm test:pwsh:all` 重新成为可靠、可读、可持续使用的本地质量门禁（see brainstorm: `docs/brainstorms/2026-03-14-pwsh-test-optimization-brainstorm.md`）。

本次规划明确延续 brainstorm 的六个关键决策：

1. 保持 `test:pwsh:all` 的质量门禁定位，不退回到默认 `fast` / smoke 组合。
2. 保持 `pnpm qa` 继续承担快速反馈，不把它和提交门禁混用。
3. 默认控制台输出保留测试文件 / 套件级进度摘要，但隐藏测试外杂项输出。
4. 被隐藏的杂项输出默认既不展示也不落盘；只有显式调试模式才产生详细输出。
5. 第一优先级是降低 `pnpm test:pwsh:all` 总时长，因此主线采用“热点测试瘦身优先”而不是“先补耗时可见性”。
6. 如果 Linux `full` 的 coverage 收尾异常最终确认属于 Pester / 容器兼容问题，则由 Host `full` 承担 coverage，Linux `full` 保留 full 断言回归（see brainstorm: `docs/brainstorms/2026-03-14-pwsh-test-optimization-brainstorm.md`）。

这不是一次“把测试改轻”的重定义，而是让现有 full 级别验证在保留价值的前提下变得稳定、安静、可重复。

## Problem Statement

当前问题已经通过本地复现被具体化，而不是抽象的“测试有点慢”：

- Host `full` 实测约 `271s`，明显超出本地提交前回归的舒适区。
- Linux `full` 实测约 `32s` 即失败，导致 `pnpm test:pwsh:all` 不能稳定作为门禁使用。
- 正常通过的测试日志中存在大量 `Write-Host`、`Write-Warning`、`WhatIf` 预演输出，影响失败定位和耗时阅读。
- `test:pwsh:all` 当前使用 `--kill-others-on-fail`，一侧先失败就会中断另一侧，降低跨环境门禁的定位价值。

与本计划最相关的已知事实和代码入口：

- 测试命令入口位于 `package.json:23-41`。
- Pester 模式切换、tag 过滤、coverage 与输出级别在 `PesterConfiguration.ps1:37-115`。
- Linux 容器测试入口与运行环境在 `docker-compose.pester.yml:8-51`。
- `test:pwsh:all` 的命令层职责已经由上一份计划与 solution 文档固定为“并发 host full + linux full 的跨环境完整验证”，不应退化为 `fast` 语义（`docs/plans/2026-03-14-004-refactor-align-pwsh-test-commands-plan.md`, `docs/solutions/workflow-issues/pwsh-test-command-alignment-system-20260314.md`）。

本地复现得到的直接基线：

- Host `full`：`psutils/tests/test.Tests.ps1` 约 `174s`，`psutils/tests/install.Tests.ps1` 约 `49s`，`psutils/tests/hardware.Tests.ps1` 约 `25s`，是最主要热点。
- 单文件 `fast`：`psutils/tests/test.Tests.ps1` 仍约 `117s`，说明其慢主要来自测试实现 / 命令探测 / 环境检查，而非 coverage。
- Linux `full`：`psutils/tests/proxy.Tests.ps1` 中两个 `test` 场景因 `curl` 命令假设失败；随后 Pester code coverage 收尾报出 `Normalize-Path` 空字符串异常。

## Research Summary

### Repo Research

- `package.json:23-41` 已将 root PowerShell 测试命令统一到 `test:pwsh:*`；这意味着本次工作应修复和优化现有命令族，而不是重新设计命名或引入新入口。
- `docs/local-cross-platform-testing.md` 已把 `test:pwsh:all` 定义为提交前跨环境完整验证入口，并明确 Host / Linux 输出隔离策略。
- `docs/plans/2026-03-05-qa-speed-design.md` 已经把 `qa:pwsh` 固定为“快速质量门 + 降噪”定位，因此本计划不能把 `qa` 重新拖回重型回归。
- `docs/plans/2026-03-14-004-refactor-align-pwsh-test-commands-plan.md` 已将 `test:pwsh:all` 的职责边界写死为 full 级别 host + Linux 并发验证；本次只能在该语义内部修复和提速。

### Institutional Learnings

最相关的历史经验来自以下文档：

1. `docs/solutions/workflow-issues/pwsh-test-command-alignment-system-20260314.md`
   - `qa` 不是完整回归，PowerShell 测试入口必须继续保持“测试域 -> 环境 -> 强度”分层。
   - `test:pwsh:all` 的失败可读性与 fail-fast 行为应保留，不应用模糊入口掩盖 Linux 和 coverage 问题。

2. `docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md`
   - Linux / macOS 上的很多失败来自测试自身携带的 Windows 假设，而非业务实现本身损坏。
   - fake CLI、`PATH` 隔离、空 `PATHEXT`、平台特定安装提示，都必须按目标平台建模。

3. `docs/solutions/performance-issues/command-discovery-regression-profile-20260314.md`
   - 性能敏感路径应优先避免 `Get-Command -CommandType Application` 这类高成本缺失命令探测。
   - `Find-ExecutableCommand` 这类轻量路径已被证明能显著降低冷启动 / 命令探测成本。

4. `docs/solutions/developer-experience/benchmark-interactive-selection-psutils-20260314.md`
   - 交互式工具能力应下沉为公共模块，避免脚本各自复制探测与降级逻辑。
   - 轻量探测路径中同样不应回退到 `Get-Command`。

### External Research Decision

本议题是高度仓库内生的测试工作流、Pester 配置与本地容器 harness 调整，且已有强本地上下文、既有计划与 solution 文档可直接引用，因此本次规划跳过外部研究。

## Proposed Solution

采用与 brainstorm 一致的 **Approach A**：热点测试瘦身优先，门禁语义不变，并预留 Linux coverage 的务实降级口。

方案拆为三条并行但有主次之分的实现线：

### 1. 以热点测试瘦身为主线，直接压缩 Host 总时长

- 以 `psutils/tests/test.Tests.ps1`、`psutils/tests/install.Tests.ps1`、`psutils/tests/hardware.Tests.ps1` 为首批优化对象，先打最主要的 Host 时间热点。
- 优先减少重复命令探测、模块探测和真实环境分支判断，改用现有轻量 helper、测试 fixture、受控 mock 或更小范围的真实验证。
- 对 `hardware` 这类上下文敏感测试，同时加强测试隔离，避免“单跑失败、整套跑通过”这类稳定性问题继续稀释性能收益。
- 保持 full 测试集合不缩水，不通过删测试、降级为 fast 或回避 Linux 路由来换时间。

### 2. 以输出治理作为配套项，改善门禁阅读体验

- 识别当前 full 日志中的高频低价值输出来源，例如缓存统计、路径同步 WhatIf、代理状态打印、性能测试打印、benchmark 选择过程打印。
- 将“诊断性但不影响通过/失败判断”的输出迁移到更合适的通道，例如 `Verbose`、调试模式、或测试内 mock / 抑制。
- 默认控制台保留测试文件 / 套件级进度摘要、失败详情、关键 warning 与最终汇总。
- 默认模式下不生成 `test.log` 一类详细落盘日志；详细输出只在显式 `debug` / `detailed` 路径下生成。

### 3. 修复 Linux `full` 稳定性，确保重门禁仍然可靠

- 修复 `psutils/tests/proxy.Tests.ps1` 在 Linux 容器中对 `curl` 的假设，使其在无 `curl` / PowerShell 别名差异环境下仍可稳定测试。
- 追踪 Linux `full` 中 Pester coverage 收尾的 `Normalize-Path` 异常。
- 如果该异常确认是 Pester / 容器兼容问题而非仓库逻辑，保留 Host `full` 覆盖率，调整 Linux `full` 为“不跑 coverage 的 full 断言回归”，并同步更新文档与期望。
- 重新审视 `test:pwsh:all` 的聚合编排，避免 Linux 先失败就直接杀掉 Host 路由，导致拿不到另一侧的完整结论与产物。

## Technical Approach

### Architecture

本次不改动 `test:pwsh:all` 的命令入口结构，继续复用现有调用链：

```text
pnpm test:pwsh:all
  -> concurrently(host, linux)
    -> pnpm test:pwsh:full
      -> pwsh -NoProfile -Command
        -> PesterConfiguration.ps1
        -> Invoke-Pester
    -> pnpm test:pwsh:linux:full
      -> docker compose -f docker-compose.pester.yml run --rm pester-full
        -> pwsh -NoProfile -Command
          -> PesterConfiguration.ps1
          -> Invoke-Pester
```

变化主要发生在三层：

1. **测试与模块代码层**：修复 Linux 假设、减少高成本探测、收口噪音输出。
2. **Pester 配置 / Docker harness 层**：只在必要时调整 Linux coverage 责任边界。
3. **文档与协作约定层**：把新的 coverage 责任与日志语义写回活文档。

### Implementation Phases

#### Phase 1: Host Hotspot Reduction

**目标**

- 显著降低 Host `full` 的总耗时，并消除最重热点文件对整体时长的支配。

**主要任务**

- `psutils/tests/test.Tests.ps1` + `psutils/modules/test.psm1`
  - 减少 `Test-EXEProgram`、`Test-ApplicationInstalled`、`Test-MacOSCaskApp`、`Test-HomebrewFormula` 的重复真实命令探测。
  - 在测试场景中引入更可控的 fixture / mock，避免几十次命令未命中探测叠加到 full 链路。
  - 优先评估是否可复用 `Find-ExecutableCommand` 类轻量 helper。
- `psutils/tests/install.Tests.ps1` + `psutils/modules/install.psm1`
  - 避免 `Get-Module -ListAvailable`、安装检测与 CLI 安装状态探测在同一套测试里反复走真实环境路径。
  - 调整测试结构，使逻辑验证与真实探测验证解耦。
- `psutils/tests/hardware.Tests.ps1` + `psutils/modules/hardware.psm1`
  - 加强平台 mock 与状态清理，避免上下文敏感失败。
  - 减少非必要的真实系统探测次数，保留少量具代表性的真实分支验证。
- `PesterConfiguration.ps1`
  - 保持 full / fast / qa 的职责边界，不把性能问题简单转嫁给模式切换。

**Success Criteria**

- Host `full` 耗时较当前基线有显著下降。
- `psutils/tests/test.Tests.ps1` 不再长期占据 Host `full` 的绝对主导时长。
- 热点优化不依赖缩减 full 测试覆盖面，不以移除 `proxy.Tests`、降级 `all` 为代价。

#### Phase 2: Output Noise Reduction

**目标**

- 保持 full 测试可诊断，但明显减少与失败定位无关的噪音。

**主要任务**

- `psutils/tests/cache.Tests.ps1`
  - 处理重复缓存统计和清理打印，避免 full 日志被同类状态块刷屏。
- `tests/Sync-PathFromBash.Tests.ps1`
  - 抑制 `WhatIf` 和路径缓存写入在正常通过场景中的重复打印。
- `psutils/tests/proxy.Tests.ps1`
  - 抑制状态打印和代理测试场景中的用户展示型输出。
- `psutils/tests/profile_windows.Tests.ps1`
  - 将性能打印收口到更明确的调试/性能模式，避免常规 full 被吞没。
- 相关模块 / 脚本
  - 优先把“仅用于人工观察”的输出改到 `Verbose`、专门 debug 模式或测试内 mock。

**Success Criteria**

- `Normal` 输出下保留每个测试文件 / 套件级进度摘要、失败详情和汇总。
- 常规通过日志中不再出现大量重复缓存统计、路径同步 `WhatIf` 和非必要状态打印。
- 默认模式下不产生详细落盘日志；`debug` / `detailed` 路径仍能提供排错信息，不牺牲可诊断性。

#### Phase 3: Linux Stability Baseline

**目标**

- 让 `pnpm test:pwsh:linux:full` 稳定结束，不再因为 `proxy.Tests` 和 coverage 收尾问题直接红掉。

**主要任务**

- `psutils/tests/proxy.Tests.ps1`
  - 将 `test` 场景改为 mock 更稳定的调用边界，不依赖宿主是否存在裸 `curl` 命令。
  - 明确 Windows alias / Linux 原生命令差异下的断言策略。
- `psutils/modules/proxy.psm1`
  - 检查 `Set-Proxy -Command test` 的命令探测和 fallback 顺序，避免测试与真实行为耦合到不可控的外部命令存在性。
- `docker-compose.pester.yml`
  - 若覆盖率收尾异常确认是容器 / Pester 问题，则在 Linux full 容器路径上关闭 coverage，同时保留 full 测试集合与非零退出码。
- `package.json`
  - 调整 `test:pwsh:all` 的聚合行为，确保 host / linux 两路结果与摘要都能落地，再统一决定退出码。
- `docs/local-cross-platform-testing.md`
  - 如果 Linux full 不再承担 coverage，要同步调整覆盖率说明和 `test:pwsh:all` 的语义描述。
- `openspec/specs/local-cross-platform-pester-testing/spec.md`
  - 如果 `linux:full` 的 coverage 责任发生变化，要同步修正规范描述，避免实现与正式 spec 脱节。
- `openspec/specs/pester-test-performance/spec.md`
  - 若 full 模式的输出或性能目标定义发生变化，要同步校准规范。
- `openspec/specs/pester-coverage-50/spec.md`
  - 若 coverage 责任收敛到 Host `full`，需要明确 50% coverage 规范绑定的验证入口。

**Success Criteria**

- `pnpm test:pwsh:linux:full` 在本地容器稳定通过。
- `pnpm test:pwsh:all` 在 Linux 路由上不再出现 `proxy.Tests` 的 `curl` 失败。
- coverage 边界如果改变，文档同步更新且未造成“Linux 其实没覆盖率但文档仍写有覆盖率”的失真。
- `pnpm test:pwsh:all` 能保留 host / linux 两路的最终结论，而不是在首个失败后直接丢失另一侧结果。

## Alternative Approaches Considered

### Approach B: 只先修 Linux，延后性能优化

**Rejected because**

- 能恢复门禁可用性，但 Host `full` 仍会长期维持高耗时。
- 用户当前的诉求包含“两个测试速度都比较慢”，只解决 Linux 会留下同样明显的日常痛点。

### Approach C: 直接把 `all` 改成 `host full + linux fast` 或双 `fast`

**Rejected because**

- 与 brainstorm 中“质量门禁优先”的结论相冲突（see brainstorm: `docs/brainstorms/2026-03-14-pwsh-test-optimization-brainstorm.md`）。
- 会把当前问题从“真实缺陷可见”重新改回“问题被隐藏到 CI”。

### Remove `proxy.Tests`

**Rejected because**

- 实测显示 `proxy.Tests` 不是主要耗时来源。
- 当前价值在于修复 Linux 假设和收口输出，而不是通过删除测试绕开问题。

## SpecFlow Analysis

### User Flow Overview

1. **本地开发者执行 `pnpm test:pwsh:full`**
   - 期望看到完整 Host 验证、覆盖率与可读日志。
   - 不能被高频无价值输出掩盖真实失败。

2. **本地开发者执行 `pnpm test:pwsh:linux:full`**
   - 期望得到可复现的 Linux 容器结果，而不是被 Windows 假设或 coverage 清理异常打断。

3. **本地开发者执行 `pnpm test:pwsh:all`**
   - 期望 host / linux 两路输出可区分、任一路失败返回非零退出码、提交前一次完成跨环境验证。
   - 期望默认输出能看到测试文件 / 套件级进度摘要，但不会被测试外杂项输出淹没。

4. **Docker 不可用**
   - 期望文档明确 fallback，而不是对 `all` 的失败原因感到困惑。

5. **调试路径**
   - 需要在 `debug` / `detailed` / 单文件运行中保留足够诊断信息，避免为了降噪把调试能力一起删掉。

### Missing Elements & Gaps

- **Coverage boundary**
  - 需要在计划中明确：Linux coverage 若关闭，是“诊断性务实降级”，不是整体回归语义退化。
- **Aggregate semantics**
  - 需要在计划中明确：质量门禁定位不只是标签可区分，还应尽量保留 host / linux 两路的最终结论与关键产物。
- **Noise definition**
  - 需要明确哪些输出属于应保留信号，哪些属于可迁移到 verbose/debug 的噪音。
  - 需要明确默认模式不生成详细落盘日志，避免再引入新的 `test.log` 依赖。
- **Performance target**
  - 需要在同一台机器 / 同一容器基线下记录 before/after，而不是用模糊的“感觉变快了”。
- **Context-sensitive tests**
  - `hardware.Tests` 单跑失败说明仍存在隔离缺口，计划必须把“稳定性”纳入性能线，而不是只看总时长。

### Critical Questions Requiring Clarification

当前无阻塞性开放问题。唯一关键分歧已在 brainstorm 中解决：

- 若 Linux coverage 异常确认属于 Pester / 容器兼容问题，则接受由 Host `full` 承担 coverage，Linux `full` 只保留 full 断言回归（see brainstorm: `docs/brainstorms/2026-03-14-pwsh-test-optimization-brainstorm.md`）。

实施时需要满足一个证据门槛：

- 只有在确认 Linux coverage 崩溃来自 Pester / 容器兼容问题，而不是仓库逻辑时，才能把 coverage 责任收敛到 Host `full`。

## System-Wide Impact

### Interaction Graph

- `pnpm test:pwsh:all`
  - 触发 `package.json` 中的 `concurrently`
  - 并发调用 Host `pwsh -> PesterConfiguration.ps1 -> Invoke-Pester`
  - 并发调用 Linux `docker compose -> pwsh -> PesterConfiguration.ps1 -> Invoke-Pester`
- 输出层
  - 当前依赖 `concurrently` 标签区分 host / linux
  - 当前 `--kill-others-on-fail` 会在首个失败时中断另一侧
  - full 日志中同时混入模块级 `Write-Host`、`Write-Warning`、`WhatIf` 输出
  - 后续需要保留文件 / 套件级进度摘要，同时把测试外杂项输出迁移到显式调试路径
- 文档层
  - `docs/local-cross-platform-testing.md`、`CLAUDE.md`、`AGENTS.md` 与相关 OpenSpec 都对 `all` / `full` / coverage 语义有引用，行为变化必须同步回写

### Error & Failure Propagation

- Host 路由
  - 测试失败或 coverage 门槛不达标会返回非零退出码。
- Linux 路由
  - 当前同时存在断言失败和 coverage 收尾失败两类红灯。
  - 若 Linux coverage 被移除，则 Linux 路由应只在断言失败或容器执行失败时返回非零。
- 聚合路由
  - `test:pwsh:all` 需要继续保持任一路失败即整体失败。
  - 但聚合层不应再因为首个失败过早中断另一侧，导致最终缺少完整诊断结果。

### State Lifecycle Risks

- Host 结果文件写入项目根目录 `testResults.xml`。
- Linux 容器结果文件写入 named volume 中的 `testResults-linux.xml`。
- 如果 Linux coverage 边界变化，必须确认不会引入新的 artifact 命名冲突，也不会让 CI / 本地工具误以为两路都仍然产出覆盖率。

### API Surface Parity

以下面向开发者的接口需要保持语义一致：

- `package.json`
- `PesterConfiguration.ps1`
- `docker-compose.pester.yml`
- `docs/local-cross-platform-testing.md`
- `README.md`
- `CLAUDE.md`
- `AGENTS.md`

### Integration Test Scenarios

1. `pnpm test:pwsh:full` 单独通过，且保留 Host coverage。
2. `pnpm test:pwsh:linux:full` 单独通过，不再因 `proxy.Tests` / coverage 收尾崩溃。
3. `pnpm test:pwsh:all` 并发执行时，host / linux 日志仍可区分，退出码正确。
4. `pnpm test:pwsh:all` 在任一路失败时仍能保留两路最终结论与关键产物。
5. 单文件热点测试使用 `PWSH_TEST_PATH` 运行时行为稳定，可作为性能基线工具。
6. Docker 不可用时，文档对 fallback 的说明与实际脚本行为一致。

## Acceptance Criteria

- [x] `pnpm test:pwsh:all` 继续保持 `host full + linux full` 并发语义，不回退为 `fast` 组合。
- [x] `psutils/tests/test.Tests.ps1`、`psutils/tests/install.Tests.ps1`、`psutils/tests/hardware.Tests.ps1` 都有 before/after 基线记录，并完成至少一轮定向优化。
- [x] `psutils/tests/proxy.Tests.ps1` 在 Linux 容器中不再因 `curl` 命令假设失败。
- [x] `pnpm test:pwsh:linux:full` 不再因为 code coverage 收尾的 `Normalize-Path` 异常失败；若采用 Host-only coverage 边界，则相关文档已同步说明。
- [x] `pnpm test:pwsh:all` 在任一路失败时仍能保留 host / linux 两路的最终结论，不再因聚合层过早中断而丢失另一侧诊断信息。
- [ ] `Normal` 输出下保留文件 / 套件级进度摘要、失败详情与最终汇总，同时显著减少重复缓存统计、路径同步 `WhatIf`、代理状态打印和非必要性能打印。
- [x] 默认模式不生成 `test.log` 一类详细落盘日志；详细输出仅在显式调试模式开启时产生。
- [x] 热点优化不通过删除 `proxy.Tests`、移除 Linux 路由或缩减 `full` 测试语义来达成。
- [x] `pnpm qa` 继续通过，`qa:pwsh` 的快速质量门职责不被破坏。
- [ ] 若 `full` 与 coverage 的绑定语义发生变化，相关 OpenSpec、README、CLAUDE、AGENTS 与本地测试文档全部同步更新。

## Success Metrics

- 在同一台 Windows 主机上，`pnpm test:pwsh:full` 目标从当前约 `271s` 降到 `180s` 以内；若最终无法达到，必须附带热点阻塞说明与 before/after 数据。
- 在同一台 Windows 主机上，`pnpm test:pwsh:all` 目标较当前基线显著下降，且主导耗时仍然来自 `host full` 而不是新的日志 / 聚合开销。
- 在同一台 Windows 主机上，`psutils/tests/test.Tests.ps1` 的 `fast` 单文件运行目标从当前约 `117s` 降到 `60s` 以内。
- 在同一台 Windows 主机上，`psutils/tests/install.Tests.ps1` 的 `fast` 单文件运行目标从当前约 `11.4s` 降到 `6s` 以内。
- `pnpm test:pwsh:linux:full` 在同一 Docker 环境中稳定通过，且不再出现 coverage 收尾崩溃。
- `test:pwsh:all` 的通过日志中，重复低价值输出块数量显著下降，失败源可在一屏内定位，且默认无额外详细日志落盘副作用。

## Validation Notes

- 2026-03-15 本地基线与结果：
  - `psutils/tests/test.Tests.ps1`（fast, 单文件）从约 `29.18s` 降到约 `12.32s`；其中最重的 `brew` 缺失探测场景从约 `22.06s` 降到子秒级。
  - `psutils/tests/install.Tests.ps1`（fast, 单文件）从约 `20.09s` 降到约 `3.58s`；最慢的“安装未安装模块”场景从约 `16.63s` 降到约 `0.135s`。
  - `psutils/tests/hardware.Tests.ps1`（fast, 单文件）从“失败且约 `39-49s`”收敛到稳定通过，单文件约 `4.66s`。
- 2026-03-15 验证命令：
  - `pnpm qa`
  - `pnpm test:pwsh:all`
- 2026-03-15 观测：
  - `pnpm test:pwsh:all` 通过，host 与 linux 两路均完整结束。
  - Host `full` 的主要时间热点已不再集中在 `test.Tests.ps1`、`install.Tests.ps1`、`hardware.Tests.ps1`。
  - 默认输出中的无关提示已减少，但 `WhatIf` 主机提示和少量 warning 仍有残留，后续可继续收口。

## Dependencies & Prerequisites

- Docker Desktop / `docker compose`
- 容器内 Pester 5.7.1 行为与 Host Pester 行为差异
- 既有轻量命令探测能力，例如 `psutils/modules/commandDiscovery.psm1`
- 可复用的测试路径覆盖机制：`PWSH_TEST_PATH`

## Risk Analysis & Mitigation

- **风险：Linux coverage 关闭后被误解为“Linux 测试缩水”。**
  - 缓解：只在根因确认为 Pester / 容器兼容问题时执行；明确由 Host `full` 承担 coverage 责任；文档同步说明。

- **风险：为了降噪过度抑制 warning，真实行为问题被隐藏。**
  - 缓解：只迁移明显的用户展示型输出和重复状态打印；失败详情、关键 warning、debug 模式输出必须保留。

- **风险：热点优化引入测试语义漂移。**
  - 缓解：优先减少重复探测与隔离问题，不先动断言目标；任何需要缩减真实环境覆盖的改动都必须用单文件 before/after 数据支撑。

- **风险：`hardware.Tests` 的上下文敏感失败会拖慢定位。**
  - 缓解：把“单跑稳定性”作为性能优化前置条件；必要时先修状态清理和模块 mock 边界。

## Documentation Plan

- `docs/local-cross-platform-testing.md`
  - 更新 Linux `full` 是否承担 coverage 的说明。
  - 更新 `test:pwsh:all` 对 coverage 的职责描述。
- `openspec/specs/local-cross-platform-pester-testing/spec.md`
  - 更新 full / Linux / artifact / fallback 的规范表述。
- `openspec/specs/pester-test-performance/spec.md`
  - 更新 full 模式下对输出与性能目标的规范说明。
- `openspec/specs/pester-coverage-50/spec.md`
  - 明确 coverage 责任绑定哪条命令验证。
- `README.md`
  - 若用户可见行为变化（例如 full 输出更安静、Linux coverage 责任调整），同步更新命令说明。
- `CLAUDE.md`
  - 保持测试工作流说明与当前事实一致。
- `AGENTS.md`
  - 如果“pwsh 改动提交前执行 `test:pwsh:all`”的语义发生细节变化，需同步回写。
- `docs/solutions/`
  - 实施完成后补一篇新的 solution，沉淀“Linux coverage 边界”和“热点测试提速”的真实结论。

## Sources & References

### Origin

- **Brainstorm document:** `docs/brainstorms/2026-03-14-pwsh-test-optimization-brainstorm.md`
  - Carried-forward decisions:
    - 保持 `test:pwsh:all` 的质量门禁定位
    - 以热点提速为第一优先级，Linux 稳定性与输出治理作为配套线
    - 默认控制台保留测试文件 / 套件级进度摘要，隐藏输出不展示也不落盘
    - Linux coverage 若属 Pester / 容器兼容问题，则由 Host `full` 承担 coverage

### Internal References

- `package.json:23-41`
- `PesterConfiguration.ps1:37-115`
- `docker-compose.pester.yml:8-51`
- `psutils/tests/proxy.Tests.ps1:251-267`
- `psutils/modules/proxy.psm1`
- `psutils/tests/test.Tests.ps1`
- `psutils/modules/test.psm1:48-544`
- `psutils/tests/install.Tests.ps1`
- `psutils/modules/install.psm1:7-396`
- `psutils/tests/hardware.Tests.ps1`
- `psutils/modules/hardware.psm1:24-416`
- `docs/plans/2026-03-05-qa-speed-design.md`
- `docs/plans/2026-03-14-004-refactor-align-pwsh-test-commands-plan.md`
- `docs/local-cross-platform-testing.md`

### Institutional Learnings

- `docs/solutions/workflow-issues/pwsh-test-command-alignment-system-20260314.md`
- `docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md`
- `docs/solutions/performance-issues/command-discovery-regression-profile-20260314.md`
- `docs/solutions/developer-experience/benchmark-interactive-selection-psutils-20260314.md`

### External References

- 本次计划未引入外部资料，原因是问题域完全围绕仓库现有测试工作流、Pester 配置和容器 harness，且本地上下文已足够完整。
