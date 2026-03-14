---
date: 2026-03-14
topic: dependabot-config-optimization
---

# Dependabot 配置优化与分层更新策略

## What We're Building

我们要把当前偏“尽量少打扰”的 `.github/dependabot.yml`，整理成一份更清晰的分层更新策略。目标不是单纯增加更多规则，而是让不同类型的依赖拥有符合实际风险和维护成本的节奏：GitHub Actions 单独维护，主 `pnpm` monorepo 走平衡节奏，仓库中相对边缘的 `config/software/mpv/mpv_scripts` 单独低频维护。

这次讨论聚焦在“更新边界与节奏”而不是具体 YAML 细节。根据仓库现状，主仓库依赖分布在根目录、`projects/**`、`scripts/node`，同时还存在一个未纳入当前 Dependabot 范围的 `config/software/mpv/mpv_scripts` Node 子项目。我们要补齐这部分覆盖，并让 major 更新进入“可见但不扰民”的节奏，而不是继续和 minor/patch 混在同一套策略里。

## Why This Approach

讨论过三条路径：极简平衡、分层平衡、强控制型。最终选择分层平衡，因为它能同时解决当前配置最值得修正的三个问题：覆盖范围不完整、调度表达不够明确、以及 monorepo 多目录更新的 PR 粒度仍有优化空间。

极简平衡虽然改动最少，但会继续把主仓库和边缘子项目混在一起看待；强控制型则会把规则拆得过细，后续维护成本偏高，也容易超出当前仓库规模真正需要的复杂度。分层平衡更符合这套仓库的实际结构：既有主 `pnpm` workspace，也有独立 Node 子项目；既有 CI 工作流依赖，也有开发工具链依赖。它在 YAGNI 和可维护性之间更稳。

## Key Decisions

- 保留 `github-actions` 与 `npm` 分离的维护边界，不把 CI 依赖和普通 Node 依赖混在同一更新器中。
- 主 `npm` 更新器继续覆盖根目录、`projects/**` 与 `scripts/node`，并按 monorepo 思路进一步减少跨目录重复 PR。
- `config/software/mpv/mpv_scripts` 单独配置为独立更新器，不与主仓库依赖合并处理。
- `config/software/mpv/mpv_scripts` 使用季度频率，作为低频更新通道。
- 主仓库的 minor/patch 更新继续以分组降噪为主，major 更新不忽略，但通过 cooldown 明显放缓。
- 调度配置要改成与当前 Dependabot 行为一致且语义明确的写法，避免继续保留容易误导的时间表达。
- 现有 `ignore` 规则应只保留真正有明确维护策略支撑的条目；没有实际使用或缺少策略背景的忽略项需要在 planning 阶段复核。

## Resolved Questions

- 总体方向选择分层平衡，而不是极简平衡或强控制型。
- `config/software/mpv/mpv_scripts` 需要纳入 Dependabot 管理，但不与主仓库依赖混在一起。
- `config/software/mpv/mpv_scripts` 的更新频率采用季度节奏。
- major 版本更新不直接忽略，而是延后处理。
- 当前阶段先确定更新边界、优先级和频率，不在 brainstorm 中锁死具体 YAML 参数值。

## Open Questions

- 暂无。`cooldown` 的具体天数、是否保留个别 `ignore` 项、是否额外设置 `open-pull-requests-limit`，都属于 planning 阶段可以落地的实现细节，不影响当前方案边界。

## Next Steps

-> `/ce:plan` 将当前结论转成 `.github/dependabot.yml` 的具体改动方案，包括调度字段、分组标识、cooldown 参数、`mpv_scripts` 独立更新器以及验证步骤
