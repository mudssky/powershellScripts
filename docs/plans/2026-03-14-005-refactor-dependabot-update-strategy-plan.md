---
title: refactor: optimize dependabot update strategy
type: refactor
status: active
date: 2026-03-14
origin: docs/brainstorms/2026-03-14-dependabot-config-optimization-brainstorm.md
---

# refactor: optimize dependabot update strategy

## Overview

整理 `.github/dependabot.yml`，将当前偏“尽量少打扰”的单层更新策略调整为更清晰的分层策略（see brainstorm: `docs/brainstorms/2026-03-14-dependabot-config-optimization-brainstorm.md`）。目标不是增加更多规则，而是让不同依赖域拥有与风险和维护成本相匹配的节奏：GitHub Actions 单独维护，主 `pnpm` monorepo 维持平衡节奏，`config/software/mpv/mpv_scripts` 作为独立 TypeScript 项目低频维护。

本计划只覆盖 Dependabot 配置和与之直接相关的说明文本，不扩展到依赖升级本身，也不顺手清理无关 CI 或 workspace 结构。重点是把更新边界、频率、major 延后策略、分组规则和目录覆盖定义清楚，并为后续实现提供一套能直接落地的修改清单与验证标准。

## Problem Statement / Motivation

当前配置与仓库实际结构之间存在几处不对齐：

- 当前 `.github/dependabot.yml` 只有 `github-actions` 与主 `npm` 两个更新器，尚未覆盖 `config/software/mpv/mpv_scripts/package.json` 这个独立 Node 子项目。
- 主 `npm` 更新器的注释仍在说“packages/apps”，但仓库真实 workspace 结构来自 `pnpm-workspace.yaml`，只包含 `projects/**` 与 `scripts/node`，说明注释和目录边界已经漂移。
- 主 `npm` 更新器同时定义了 `all-minor-patch` 和 `linting` 两套分组，但当前 catch-all 非破坏性分组已经承担了大部分降噪职责，`linting` 组缺少明确收益。
- 现有 ignore 中的 `@typescript/native-preview` 与根目录 `package.json` 相符，但 `react` 在当前仓库未检出实际依赖，疑似遗留规则。
- 远端存在多条 stale Dependabot 分支，说明仓库已经真实经历过 PR 噪音或遗留清理问题，继续维持“看起来能用”的配置并不能保证后续维护体验。

另外，`mpv_scripts` 目录当前同时存在 `pnpm-lock.yaml` 与 `package-lock.json`，而其 `packageManager` 字段声明的是 `pnpm`。这不一定需要在本次计划里直接清理，但必须作为 Dependabot 接入时的显式风险记录下来，避免实现阶段默认“只有一份锁文件会被改”。

## Proposed Solution

### 1. 把 Dependabot 更新拓扑重组为三层

将当前配置收敛为 3 个更新器：

1. `github-actions`
2. 主仓库 `npm` / `pnpm` monorepo
3. `config/software/mpv/mpv_scripts` 独立 `npm` 项目

这样做的核心收益是把“CI 依赖”“主开发工具链依赖”“边缘独立项目依赖”三种噪音源拆开。后续 reviewer 看到 PR 标题、变更目录和 cadence 时，不需要再从 diff 倒推这是哪类维护动作。

### 2. 为三层更新器定义不同节奏

按当前讨论结果，更新频率收敛为：

- `github-actions`: 每周一次，保留 `Asia/Shanghai` 维护窗口，优先保证 CI 依赖不过旧
- 主仓库 `npm`: 每月一次，维持“可审阅但不过载”的主节奏
- `mpv_scripts`: 每季度一次，低频维护

实现时优先使用 GitHub 官方当前支持的原生 `schedule.interval` 值，而不是在没有必要时切到 `cron`。截至 2026-03-14 的官方文档，`weekly`、`monthly`、`quarterly` 都属于支持范围，因此本计划不引入自定义 cron 表达式。

### 3. 主 `npm` 更新器只对 non-breaking 更新做集中降噪

主更新器继续覆盖：

- `/`
- `/projects/**`
- `/scripts/node`

并把 minor/patch 更新收敛为一个主分组，优先采用官方支持的 `groups.group-by: dependency-name` 来减少 monorepo 多目录中“同一个依赖拆成多个 PR”的情况。该分组只服务 non-breaking 更新；major 更新不合并进这个大组里，避免把多个破坏性升级打包进同一个 PR。

当前 `linting` 组不再作为默认保留项。除非实现阶段发现它能带来明确可读性收益，否则应移除这类与 catch-all non-breaking 组重叠的规则，保持配置最小化。

### 4. major 更新延后，但不隐藏

主仓库 `npm` 与 `mpv_scripts` 都不直接忽略 semver-major 更新，而是通过 `cooldown` 明显放缓，使 major 版本进入“可见但不扰民”的节奏。这样既保留升级信号，也不会让 reviewer 在每次常规依赖维护里同时接住大量破坏性变更。

对于 ignore：

- 保留 `@typescript/native-preview` 的明确忽略策略，因为它确实存在于根目录依赖集中
- 复核并优先移除 `react` 规则，除非实现阶段在未扫描到的目录中发现真实依赖

### 5. 为 GitHub Actions 单独做 grouped maintenance

`github-actions` 更新器继续独立存在，并将 workflow 依赖按单一组维护。当前仓库涉及的主要 Actions 位于：

- `.github/workflows/test.yml`
- `.github/workflows/qa-benchmark.yml`

这里的目标不是做更细分类，而是保证 CI 相关更新在 review 时语义一致、边界清晰，并继续保留现有 `commit-message.prefix: ci` 风格。

### 6. 同步修正文档与配置注释，避免再次漂移

至少同步修正以下内容：

- `.github/dependabot.yml` 内部注释与目录说明
- `docs/cheatsheet/github/dependabot.md` 中与当前仓库直接相关、容易被误抄为 repo 策略的部分

这里不要求把通用 cheatsheet 全量改写成 repo 专用文档，但至少要避免它继续和仓库当前配置形成明显冲突。更具体地说，若 cheatsheet 仍保留 `/packages/*`、`/apps/*` 这类示例，应该在实现时明确标注“这是通用示例，不等于本仓库当前目录布局”，或者补一段 repo-specific note。

## SpecFlow Analysis

从维护者工作流角度，这次配置至少要覆盖以下流程与失败流：

- **Flow 1: CI 依赖定期维护**
  - Dependabot 扫描 `.github/workflows/*.yml`
  - 同类 GitHub Actions 更新被合并到单一 PR
  - reviewer 可以快速判断“这是 CI 依赖维护”，不与 Node 依赖升级混淆

- **Flow 2: 主仓库 non-breaking 依赖维护**
  - Dependabot 同时扫描根目录、`projects/**` 与 `scripts/node`
  - 同名依赖在多目录中尽量归并，减少重复 PR
  - reviewer 可以把一次 PR 当成“本月主仓库安全升级/常规升级窗口”处理

- **Flow 3: major 更新进入延后通道**
  - major 更新不会被完全屏蔽
  - 但它们不会和常规 minor/patch 更新混在一起频繁打扰
  - reviewer 只在延后窗口真正到期后再处理破坏性升级

- **Flow 4: 独立 mpv 项目低频维护**
  - `mpv_scripts` 不再因为不在 workspace 而完全失去 Dependabot 覆盖
  - 同时它也不会与主 monorepo PR 节奏绑在一起

- **Flow 5: lockfile 边界不清的失败流**
  - `mpv_scripts` 同时存在 `pnpm-lock.yaml` 和 `package-lock.json`
  - 如果 Dependabot 实际会同时触发多份锁文件改动，reviewer 必须能从计划中预期这种行为，而不是把它误判成异常

由此导出的补充要求：

- 计划必须明确 `mpv_scripts` 是“独立项目、低频更新”，而不是“顺手加到主 monorepo glob”。
- 计划必须显式记录 mixed lockfile 风险，不能在实现里默默假设只会改 `pnpm-lock.yaml`。
- 计划必须约束分组逻辑保持可解释，避免为了减少 PR 数量而引入过多重叠 group。
- 计划必须要求注释和说明文本同步更新，否则配置一旦变动，仓库内现有 cheatsheet 很快会重新误导使用者。

## Technical Considerations

- 根目录 `package.json` 声明 `packageManager: pnpm@10.25.0`，workspace 由 `pnpm-workspace.yaml` 管理 `projects/**` 与 `scripts/node`。
- `config/software/mpv/mpv_scripts/package.json` 声明自己是独立 Rollup + TypeScript 项目，并在 `CLAUDE.md` 中被明确描述为 separate TypeScript project。
- 当前 `docs/cheatsheet/github/dependabot.md` 是一份 2025 年通用速查表，其中目录示例与本仓库实际布局不一致；实现若不处理，会形成“配置已改、示例仍旧”的双轨状态。
- 截至 2026-03-14 的 GitHub 官方文档已支持 `directories`、`groups`、`groups.group-by`、`cooldown` 与 `schedule.interval: quarterly`，因此本计划不依赖非官方 workaround。
- 当前仓库不存在本地可完全模拟 Dependabot 运行的现成脚本，因此验证要分为“本地静态校验”与“提交后观察首次 Dependabot 行为”两层，而不是假设能在本机完整 dry-run。
- 这次改动不涉及 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`、`PesterConfiguration.ps1` 或 `docker-compose.pester.yml`，因此不触发 `pnpm test:pwsh:all` 的提交前约定；但依然要遵守仓库对配置改动执行 `pnpm qa` 的要求。

## System-Wide Impact

- **Interaction graph**：Dependabot 新配置会直接影响 `.github/workflows/*.yml` 中 Actions 版本、根目录 `pnpm-lock.yaml`、workspace 包清单，以及 `config/software/mpv/mpv_scripts` 下的 manifest / lockfile 变更节奏。
- **Error propagation**：目录路径写错、使用不受支持的字段，或在 mixed lockfile 场景下误判 source of truth，都可能导致 Dependabot 报配置错误、静默漏扫或生成超出预期的 PR。
- **State lifecycle risks**：主仓库和 `mpv_scripts` 将分别维护自己的依赖状态；若 reviewer 不清楚这两个锁文件域互相独立，就容易把“独立项目的升级噪音”误认为主 monorepo 的异常。
- **API surface parity**：面向维护者的真实接口不只有 YAML 本身，还包括配置注释、通用 cheatsheet 和 review 预期。实现时至少要让这些入口不再互相打架。
- **Integration test scenarios**：
  - `github-actions` 更新器仍能覆盖当前 workflow 中使用的 Actions
  - 主 `npm` 更新器能继续覆盖根目录、`projects/**`、`scripts/node`
  - `mpv_scripts` 获得独立更新器，不再漏扫
  - major 更新被延后而非直接忽略
  - 根目录 `pnpm qa` 通过

## Acceptance Criteria

- [ ] `.github/dependabot.yml` 被重构为三层更新器：`github-actions`、主 `npm` monorepo、`config/software/mpv/mpv_scripts`
- [ ] `github-actions` 使用独立 cadence，并将 Actions 更新收敛为单一组，继续保留 `ci` 风格的提交信息前缀
- [ ] 主 `npm` 更新器明确覆盖 `/`、`/projects/**`、`/scripts/node`，不再保留与仓库实际布局不一致的目录说明
- [ ] 主 `npm` minor/patch 更新采用单一 non-breaking 分组，并使用 `group-by: dependency-name` 降低多目录重复 PR
- [ ] 主 `npm` major 更新不被直接忽略，而是通过 `cooldown` 延后处理
- [ ] `config/software/mpv/mpv_scripts` 被纳入独立更新器，频率为季度
- [ ] 计划或实现明确记录 `mpv_scripts` mixed lockfile 风险，不在 review 中把双锁文件改动当成“莫名其妙的异常”
- [ ] `@typescript/native-preview` 的 ignore 策略被保留；`react` ignore 被复核并在无真实依赖时移除
- [ ] `.github/dependabot.yml` 注释与 `docs/cheatsheet/github/dependabot.md` 至少有一处被同步修正，避免继续误导仓库真实策略
- [ ] 根目录 `pnpm qa` 通过

## Success Metrics

- Dependabot PR 可以从标题、目录和 cadence 快速判断“这是 CI 更新、主仓库常规依赖更新，还是 mpv 独立项目更新”。
- 主 monorepo 不再因为同名依赖分布在多个目录而产生不必要的重复 PR。
- major 更新仍然可见，但不会和常规月度维护混在一起干扰 review。
- `mpv_scripts` 不再处于“真实存在但无人维护”的灰区。
- 仓库中的说明文本不再把通用示例误表述成当前 repo 的真实策略。

## Dependencies & Risks

- 风险：`mpv_scripts` 的 mixed lockfile 状态可能让 Dependabot 生成超出预期的 diff。
  缓解：在实现前先确认 reviewer 接受“先纳入、再观察真实改动形态”的做法；如果双锁文件 churn 明显，再拆出后续清理任务，而不是在本次配置优化里顺手扩大范围。

- 风险：过度依赖 grouping 可能掩盖具体升级语义，导致 reviewer 面对过大的 PR。
  缓解：只对 minor/patch 做单一 non-breaking 分组；major 继续单独暴露并延后处理。

- 风险：同时保留 catch-all group 和细分 group 会让配置越来越难解释。
  缓解：优先采用最小规则集；没有明确价值的重叠分组不保留。

- 风险：如果只改 YAML，不同步注释或说明文档，仓库会迅速重新出现“配置真实边界”和“文档记忆边界”分离的问题。
  缓解：把 repo-specific 文本同步列入本次改动范围，哪怕只是增加一段简短说明。

- 风险：本地无法完整 dry-run Dependabot，导致实现后仍需等待平台反馈。
  缓解：实现阶段严格依赖官方当前文档字段，完成本地静态检查与 `pnpm qa` 后，在提交说明中明确“首次实际行为需观察 GitHub Dependabot 运行结果”。

## Sources & References

- **Origin brainstorm:** `docs/brainstorms/2026-03-14-dependabot-config-optimization-brainstorm.md`
  - 延续的关键决策：采用分层平衡方案；`mpv_scripts` 独立低频维护；major 更新延后但不忽略
- **Current config:** `.github/dependabot.yml`
- **Current workflows:** `.github/workflows/test.yml`, `.github/workflows/qa-benchmark.yml`
- **Workspace boundary:** `pnpm-workspace.yaml`, `package.json`
- **Separate mpv project context:** `config/software/mpv/mpv_scripts/package.json`, `CLAUDE.md`
- **Repo reference doc:** `docs/cheatsheet/github/dependabot.md`
- **Institutional learning carried forward:** `docs/solutions/workflow-issues/pwsh-test-command-alignment-system-20260314.md`
  - 延续的关键经验：配置/命令边界一旦变化，必须同步更新文档与协作约定，否则很快重新漂移
- **External references (GitHub Docs, verified on 2026-03-14):**
  - Dependabot options reference: https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference
  - `schedule` options: https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file#schedule
  - `groups` and `group-by`: https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file#groups
  - `cooldown`: https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file#cooldown
