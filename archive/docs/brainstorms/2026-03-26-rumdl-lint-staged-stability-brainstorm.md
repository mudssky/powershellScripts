---
date: 2026-03-26
topic: rumdl-lint-staged-stability
---

# Rumdl + lint-staged 稳定性方案讨论

## What We're Building

为 Windows 下大量 Markdown 文件进入暂存区时的提交前检查设计一个更稳定的方案，避免 `lint-staged` 在运行 `rumdl check --fix` 时出现批量启动、`Task failed to spawn`、`SIGKILL` 等问题。

当前仓库在根级 `lint-staged` 中直接对 `*.md` 执行 `rumdl check --fix`。当一次提交包含大量文档时，`lint-staged` 会把文件拆成多个 chunk 并并发启动多个任务，导致本地提交体验不稳定，且失败信息并不指向具体 Markdown 规则问题。

## Why This Approach

这次讨论重点不是 Markdown 规则本身，而是“Markdown 质量门应该放在哪里，以及以什么粒度运行”。仓库当前已经有显式的 `pnpm format:md` 能力，因此不一定必须把所有 Markdown 自动修复都压在 `pre-commit` 上。

我优先考虑 YAGNI：先用最小复杂度恢复稳定提交，再决定是否保留提交时的自动修复体验。

## Key Decisions

- 方案 A（推荐）: 将 Markdown 从 `pre-commit` 中移除，保留显式 `pnpm format:md`
  理由：这是最小改动，能立即消除 Windows 下批量文档提交的不稳定性；文档格式化仍可通过手动命令或 CI 承担。

- 方案 B（已选择）: 保留 `pre-commit`，但改为自定义脚本串行/分批调用 `rumdl`
  理由：需要继续保留 Markdown 的提交前自动修复能力，同时避开 `lint-staged` 在 Windows 下对大量 Markdown 文件分块并发启动所带来的 `spawn` / `SIGKILL` 不稳定问题。

- 方案 C: 继续使用 `lint-staged`，但改成函数式/分目录配置，尽量缩短单次命令与任务规模
  理由：变更相对集中，保留当前架构；但它仍依赖 `lint-staged` 的分块与调度行为，稳定性不如方案 B。

## Resolved Questions

- 是否必须在 `pre-commit` 阶段强制执行 Markdown 自动修复，而不是改为显式命令或 CI？
  结论：必须保留，因此选择方案 B。

## Open Questions

- 方案 B 应该优先追求绝对稳定，还是在稳定前提下尽量保留一定并发速度？

## Next Steps

在方案 B 下继续细化执行策略，然后进入 `/ce:plan`。
