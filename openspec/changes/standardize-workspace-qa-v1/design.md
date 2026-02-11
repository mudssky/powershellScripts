## Context

当前仓库已包含多个 Node 子项目，但 QA 入口存在命名与职责不一致：部分包使用 `biome:fixAll` 直写修复，部分包未显式区分快测与全量测试；同时 `lint-staged` 的前置规则与项目级 QA 的检查维度存在差异。该问题虽不涉及复杂系统架构，但跨越 `scripts/node`、`projects/clis/json-diff-tool` 与根级提交钩子，属于跨模块流程规范化变更，需要先明确统一契约与边界。

## Goals / Non-Goals

**Goals:**
- 定义并落地统一包级 QA 脚本接口：`typecheck:fast`、`check`、`test:fast`、`qa`。
- 让 `qa` 在各包中具备一致语义：只做快速、可重复、无交互检查。
- 对提交阶段采用 `biome check --write`，使格式与 lint 在 commit 前同步收敛。
- 统一测试颜色环境，消除颜色变量差异导致的偶发失败。
- 为 V2 引入 Turbo 保留稳定接口（不在本次引入 turbo 配置与命令）。

**Non-Goals:**
- 不在本次引入 `turbo.json`、`turbo run` 或远程缓存配置。
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

## Risks / Trade-offs

- **`qa` 由“自动修复”变为“只检查”后，首次使用可能失败更多** → 在文档与脚本中保留 `check:fix`，并保留兼容别名降低迁移成本。
- **不同终端颜色能力不一致** → 在测试配置层强制颜色并清理冲突变量。
- **未来引入 Turbo 时任务粒度可能调整** → 先固定统一脚本接口，确保 V2 只改调度层。

## Migration Plan

1. 在目标子包添加并统一 `test:fast`、`check`、`check:fix`、`qa` 脚本。
2. 保留历史别名（如 `biome:fixAll`、`biome:check`）映射到新接口，避免已有调用中断。
3. 更新 `lint-staged` 的 JS/TS 规则为 `biome check --write`。
4. 在涉及颜色断言的包内统一 Vitest 颜色环境。
5. 执行各包 `qa` 验证，并记录已知提示（如 biome schema info）是否阻断。

## Open Questions

- V2 是否将根项目 `qa:pwsh` 与子包 `qa` 合并为单一 `qa:changed` 入口？
- V2 中 Turbo 的 affected 基线使用 `origin/master` 还是可配置分支变量？
- 是否需要为未来新包提供脚手架模板，自动带上 QA 统一脚本集合？
