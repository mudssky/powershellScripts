---
date: 2026-03-14
topic: pwsh-test-optimization
---

# PowerShell 提交门禁测试提速与输出治理

## What We're Building

我们要改进 `pnpm test:pwsh:all` 这一条 PowerShell 提交前 / PR 前门禁链路，在继续保留 `host full + linux full` 重门禁定位的前提下，同时解决三个问题：

1. 两路 `full` 测试总体过慢，影响日常回归效率。
2. Linux `full` 当前存在稳定失败或收尾异常，导致聚合命令可用性不足。
3. 测试日志中有不少与“是否通过”无关的输出，阅读成本偏高。

这次探索的目标不是把门禁降级成更“轻”的 smoke 流程，因为仓库里已经有 `pnpm qa` 负责快速反馈。这里要做的是：在不削弱提交门禁语义的前提下，让 `pnpm test:pwsh:all` 更稳定、更快、更安静，并且默认输出更适合代码审查与失败定位。

## Why This Approach

实跑结果说明问题已经足够具体，可以直接围绕真实瓶颈做决策：

- Host `full` 实测约 `271s`，其中最重热点集中在 `psutils/tests/test.Tests.ps1`、`psutils/tests/install.Tests.ps1`、`psutils/tests/hardware.Tests.ps1`。
- `psutils/tests/test.Tests.ps1` 在单文件 `fast` 下仍约 `117s`，说明它的慢主要来自测试实现或真实环境探测，不是 code coverage。
- Linux `full` 实测约 `32s` 即失败，失败点稳定落在 `psutils/tests/proxy.Tests.ps1` 的 `curl` 假设，以及 code coverage 收尾阶段的 `Normalize-Path` 空字符串异常。
- 当前主要噪音来自测试与模块内的 `Write-Host`、`Write-Warning`、`WhatIf` 等非断言输出，而不是 `PesterConfiguration.ps1` 的配置对象输出。
- 使用者已经明确：`pnpm qa` 继续承担日常快速反馈；`pnpm test:pwsh:all` 是提交时或 PR 时的重门禁，默认输出应保留测试文件 / 套件级进度摘要，但隐藏测试外杂项输出；这些被隐藏内容默认既不展示也不落盘，只有调试模式才生成详细输出。

这意味着我们不该抽象地“优化测试”，而应拆成稳定性、噪音控制、热点测试瘦身三条线分别处理。

## Approaches Considered

### Approach A: 热点测试瘦身优先，门禁语义不变

保持 `pnpm test:pwsh:all` 继续作为 `host full + linux full` 的提交门禁，不把它重新降级成快测；主要直接处理最慢的 Host 热点测试文件，同时把默认杂项输出收起来，并顺手修复 Linux 已知稳定性问题。

**Pros:**

- 最符合当前“提交门禁更快”这一首要目标。
- 不需要重新解释 `qa` 与 `test:pwsh:all` 的职责边界。
- 能直接打在当前真实瓶颈上，而不是先做观测性工程。

**Cons:**

- 需要逐个处理热点测试文件，工作比较集中。
- Linux coverage 兼容问题如果是外部限制，仍需要单独定义 fallback。

**Best when:** 你把“提交门禁总时长明显下降”放在第一优先级，同时不接受把门禁退化成轻量快测。

### Approach B: 先恢复可用性与可读性，再延后时间优化

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

- 你已经明确把“总时长明显下降”放在第一优先级，而不是先补耗时报告或只做输出治理。
- `pnpm qa` 已经承担快反馈职责，没有必要再把提交门禁重新轻量化。
- Host 的主要慢点已经收敛到少数热点测试文件，适合直接定向优化。
- 输出治理可以作为同一轮工作的配套项，而不需要单独拆成新链路。

## Key Decisions

- 保持 `pnpm test:pwsh:all` 的提交门禁定位，不退回到默认 fast/smoke 组合。
- 保持 `pnpm qa` 作为快速反馈入口，不把它与提交门禁混用。
- 默认控制台输出保留测试文件 / 套件级进度摘要，但隐藏测试外杂项输出。
- 被隐藏的杂项输出默认既不展示也不落盘；只有显式调试模式才产生详细输出。
- 第一优先级是降低 `pnpm test:pwsh:all` 总时长，因此主线采用“热点测试瘦身优先”而不是“先补耗时可见性”。
- Linux 稳定性修复与输出治理作为主线配套项一起推进，但不改动门禁的基本语义。

## Resolved Questions

- Linux `full` 的 coverage 收尾异常如果最终确认属于 Pester / 容器兼容问题，而不是仓库逻辑问题，则接受“Host `full` 负责 coverage，Linux `full` 只负责跨平台 full 断言”的职责划分。

## Next Steps

→ 可进入 `/ce:plan` 形成实施清单。
