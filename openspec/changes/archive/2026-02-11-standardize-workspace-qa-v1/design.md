## Context

当前仓库已包含多个 Node 子项目，但 QA 入口存在命名与职责不一致：部分包使用 `biome:fixAll` 直写修复，部分包未显式区分快测与全量测试；同时 `lint-staged` 的前置规则与项目级 QA 的检查维度存在差异。该问题虽不涉及复杂系统架构，但跨越 `scripts/node`、`projects/clis/json-diff-tool` 与根级提交钩子，属于跨模块流程规范化变更，需要先明确统一契约与边界。

## Goals / Non-Goals

**Goals:**
- 定义并落地统一包级 QA 脚本接口：`typecheck:fast`、`check`、`test:fast`、`qa`。
- 让 `qa` 在各包中具备一致语义：只做快速、可重复、无交互检查。
- 对提交阶段采用 `biome check --write`，使格式与 lint 在 commit 前同步收敛。
- 统一测试颜色环境，消除颜色变量差异导致的偶发失败。
- 为 V2 引入 Turbo 保留稳定接口，并在不破坏既有命令的前提下新增 Turbo 命令族。

**Non-Goals:**
- V1 阶段不强制把既有 `qa`/`qa:all` 命令迁移为 `turbo run`。
- 不改造非 workspace 包（如 `config/software/mpv/mpv_scripts`）的 QA 体系。
- 不在本次统一全量测试策略（如 e2e、覆盖率门槛、慢测拆分）。

## Decisions

- **Decision 1: 采用统一脚本契约而非每包自定义命名**
  - 方案：所有纳入范围的子包统一暴露 `typecheck:fast`、`check`、`test:fast`、`qa`。
  - 原因：降低认知成本，便于后续批量执行（`pnpm --filter ... run qa` / `turbo run qa`）。
  - 备选：保留历史命名，仅在文档中约定，约束力弱且不利自动化。

- **Decision 2: 将 lint+format 聚合为 `check`，并单独提供 `check:fix`**
  - 方案：`check` 默认只校验（`biome check .`），`check:fix` 执行写入修复（`biome check --write .`）。
  - 原因：与 CI 无副作用执行一致，同时保留本地修复入口。
  - 备选：直接在 `qa` 内使用 fix 命令，容易在 CI 与并行执行中引入副作用。

- **Decision 3: `qa` 链路固定为 `typecheck:fast -> check -> test:fast`**
  - 方案：所有子包 `qa` 顺序一致，先静态类型，再规范检查，再快测。
  - 原因：失败定位路径稳定、易读，且执行成本可控。
  - 备选：各包自由排列，导致结果不一致与排障困难。

- **Decision 4: 测试颜色环境在测试框架配置层统一处理**
  - 方案：在 `vitest.config.ts` 中设置 `process.env.FORCE_COLOR ??= '1'` 并删除 `NO_COLOR`。
  - 原因：将环境差异收敛在测试入口，避免依赖调用方额外传参。
  - 备选：在命令行层传 `FORCE_COLOR=1`，跨平台可移植性与一致性较差。

- **Decision 5: 提交阶段采用 `biome check --write`**
  - 方案：`lint-staged` 对 JS/TS/CSS/HTML/JSON 规则使用 `biome check --write`。
  - 原因：提交前同时处理 lint 与格式化，减少“通过 format 但 lint 失败”的往返。
  - 备选：仅 format，仍需在后续 QA 阶段暴露 lint 问题。

- **Decision 6: V2 采用“新增 Turbo 命令，不改原命令”策略（方案 A）**
  - 方案：保留原有 `qa`、`qa:all`、`qa:verbose`、`qa:all:verbose` 语义与行为不变；新增 `turbo:qa`、`turbo:qa:all`、`turbo:qa:verbose`、`turbo:qa:all:verbose` 作为并行入口。
  - 原因：降低迁移风险，允许团队分阶段切换，出现问题时可快速回退到既有路径。
  - 备选：直接替换原命令为 Turbo，实现更“干净”，但会放大一次性迁移风险。

- **Decision 7: Turbo 变更基线复用 `QA_BASE_REF` 约定**
  - 方案：`changed` 模式中将 `QA_BASE_REF` 映射到 `TURBO_SCM_BASE`，默认仍为 `origin/master`。
  - 原因：保持使用习惯一致，降低认知切换成本，并与现有 README 约定对齐。
  - 备选：强制改为 Turbo 原生默认 `main`，会引入分支命名与文档不一致问题。

- **Decision 8: 根级 `qa:pwsh` 继续独立调度，不并入 Turbo 根任务**
  - 方案：workspace 包的 QA 由 Turbo 调度；根级 `qa:pwsh` 继续沿用现有路径变更探测逻辑。
  - 原因：PowerShell 侧变更判断已稳定，且短期内无需引入 `//#` Root Task 复杂度。
  - 备选：将 root 任务并入 Turbo，可统一图谱，但需要额外维护 root 输入边界与缓存策略。

- **Decision 9: `turbo.json` 先采用保守缓存边界**
  - 方案：先纳入 `qa`、`check`、`test:fast`、`typecheck:fast` 任务，初期使用 `outputs: []`，优先验证调度正确性。
  - 原因：该阶段关注“并排可用 + 语义一致”，避免过早引入缓存失效边界争议。
  - 备选：首版就细化 `outputs` 与远程缓存，可提升潜在收益，但调试成本更高。

## Risks / Trade-offs

- **`qa` 由“自动修复”变为“只检查”后，首次使用可能失败更多** → 在文档与脚本中保留 `check:fix`，并保留兼容别名降低迁移成本。
- **不同终端颜色能力不一致** → 在测试配置层强制颜色并清理冲突变量。
- **未来引入 Turbo 时任务粒度可能调整** → 先固定统一脚本接口，确保 V2 只改调度层。
- **Turbo 的 `--affected` 在浅克隆仓库可能误判** → CI 需要确保具备足够 Git 历史（如 `fetch-depth: 0`）。

## Migration Plan

1. 在目标子包添加并统一 `test:fast`、`check`、`check:fix`、`qa` 脚本。
2. 保留历史别名（如 `biome:fixAll`、`biome:check`）映射到新接口，避免已有调用中断。
3. 更新 `lint-staged` 的 JS/TS 规则为 `biome check --write`。
4. 在涉及颜色断言的包内统一 Vitest 颜色环境。
5. 执行各包 `qa` 验证，并记录已知提示（如 biome schema info）是否阻断。
6. 在根 `package.json` 新增 `turbo:qa*` 命令族，不修改既有 `qa*` 命令。
7. 增加 Turbo 专用编排入口（如 `scripts/qa-turbo.mjs`），对齐现有 `changed/all/verbose` 语义。
8. 在 `changed` 模式中映射 `QA_BASE_REF -> TURBO_SCM_BASE`，默认保持 `origin/master`。
9. 新增 `turbo.json` 任务图（`qa`、`check`、`test:fast`、`typecheck:fast`）并定义保守缓存边界。
10. 保持 root `qa:pwsh` 独立执行路径，验证与 Turbo workspace 调度并存时的可观测性。
11. 在 CI 侧补充 affected 运行前置（完整 Git 历史）并采集 cold/warm/changed 三类耗时。

## Open Questions

- 是否需要为未来新包提供脚手架模板，自动带上 QA 统一脚本集合？
- 是否在 V2.1 引入远程缓存（如 Vercel Remote Cache）以及缓存签名策略？
