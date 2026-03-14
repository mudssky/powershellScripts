---
date: 2026-03-14
topic: pwsh-test-optimization
---

# PowerShell 测试提速与 Linux 稳定性

## What We're Building
我们要改进 `test:pwsh:all` 这一条本地质量门禁链路，在继续保留 `host full + linux full` 定位的前提下，同时解决三个问题：

1. 两路 `full` 测试总体过慢，影响日常回归效率。
2. Linux `full` 当前存在稳定失败，导致聚合命令不可作为可靠门禁。
3. 测试日志中有不少与“是否通过”无关的输出，阅读成本偏高。

这次探索的目标不是把测试改成更“轻”的 smoke 流程，而是在不牺牲 full 回归价值的前提下，让它更稳定、更快、更安静。

## Why This Approach
实跑结果说明问题已经足够具体，可以直接围绕真实瓶颈做决策：

- Host `full` 实测约 `271s`，其中最重热点集中在 `psutils/tests/test.Tests.ps1`、`psutils/tests/install.Tests.ps1`、`psutils/tests/hardware.Tests.ps1`。
- `psutils/tests/test.Tests.ps1` 在单文件 `fast` 下仍约 `117s`，说明它的慢主要来自测试实现或真实环境探测，不是 code coverage。
- Linux `full` 实测约 `32s` 即失败，失败点稳定落在 `psutils/tests/proxy.Tests.ps1` 的 `curl` 假设，以及 code coverage 收尾阶段的 `Normalize-Path` 空字符串异常。
- 当前主要噪音来自测试与模块内的 `Write-Host`、`Write-Warning`、`WhatIf` 输出，而不是 `PesterConfiguration.ps1` 的配置对象输出。

这意味着我们不该抽象地“优化测试”，而应拆成稳定性、噪音控制、热点测试瘦身三条线分别处理。

## Approaches Considered

### Approach A: 先稳再快，按三条线并行收敛

先修 Linux `full` 的确定性失败，再收口噪音输出，最后针对热点测试做定向瘦身。

**Pros:**
- 最符合当前“质量门禁优先”的目标。
- 每一步都能独立验证，回归风险最低。
- 能直接对齐当前真实痛点，而不是重写整个测试编排。

**Cons:**
- 需要同时修改测试、模块行为和部分运行配置。
- 总体收益会分阶段出现，不是一次性大提速。

**Best when:** 你希望保留现有 `full` 语义，只接受小步、可验证的改进。

### Approach B: 先让门禁恢复可用，再延后性能优化

第一阶段只修 Linux 失败和明显噪音，让 `test:pwsh:all` 重新稳定可用；性能热点等后续再单独做。

**Pros:**
- 最快恢复门禁可用性。
- 变更范围最小，容易审查。

**Cons:**
- 慢的问题仍然会长期影响本地开发体验。
- 需要后续再开一次专门的性能优化工作。

**Best when:** 当前最紧急的是“不要再红”，而不是“尽快跑完”。

### Approach C: 重新定义双平台 full 的职责分工

把 Host `full` 作为覆盖率与深度回归主入口，把 Linux `full` 收敛为跨平台断言回归，不再承担 coverage 收尾。

**Pros:**
- 对 Linux 当前的 Pester coverage 问题最直接。
- 通常能明显降低 `all` 的不稳定性和额外成本。

**Cons:**
- 属于测试语义调整，不再是完全对称的双平台 full。
- 需要你接受“coverage 主要以 Host 为准”的规则。

**Best when:** 你更重视稳定门禁与跨平台断言，而不执着于双平台都生成 coverage。

## Recommendation
推荐 **Approach A**，但需要预留一个务实降级口：如果确认 Linux coverage 异常来自 Pester 自身而不是仓库逻辑，就把 `Approach C` 中“Host 承担 coverage、Linux 保留 full 断言”的决策作为 fallback。

推荐原因：

- Host 的主要慢点已经明确落在少数热点测试文件，适合定向优化。
- Linux 的失败点也已具象，不需要先大改架构。
- 这种做法能先保住质量门禁，再逐步把体验拉回来。

## Key Decisions
- 保持 `test:pwsh:all` 的质量门禁定位，不退回到默认 fast/smoke 组合。
- 把问题拆成三条独立工作流：Linux 稳定性、输出降噪、热点测试提速。
- 优先处理“稳定失败”和“无价值输出”，再处理纯性能问题。
- 性能优化重点应落在热点测试实现本身，而不是先从 coverage 开关入手。
- 如果确认 Linux `full` 的 coverage 收尾异常属于 Pester/容器兼容问题，则接受把 coverage 责任收敛到 Host `full`，让 Linux `full` 只保留 full 断言回归。

## Resolved Questions
- Linux `full` 的 coverage 收尾异常如果最终确认属于 Pester/容器兼容问题，而不是仓库逻辑问题，则采用“Host `full` 负责 coverage，Linux `full` 负责跨平台 full 断言”的职责划分。

## Next Steps
→ 在这个问题确认后，可进入 `/ce:plan` 或直接形成实施清单。
