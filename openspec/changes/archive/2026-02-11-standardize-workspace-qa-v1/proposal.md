## Why

当前仓库内不同子项目的 QA 脚本命名与行为不统一，导致开发者在本地与 CI 中需要记忆多套命令；同时，提交阶段与项目级 QA 的职责边界不够清晰，容易出现“提交可过但项目级检查失败”的体验割裂。需要先建立一套统一、可并行、可按项目复用的 V1 QA 契约，为后续引入 Turborepo 编排打基础。

## What Changes

- 统一 workspace 子包 QA 约定：每个包提供 `typecheck:fast`、`check`（lint/format 检查）、`test:fast`、`qa`。
- 规范 `qa` 组合方式：`typecheck:fast -> check -> test:fast`，确保包级质量入口一致。
- 调整提交前策略：`lint-staged` 对 JS/TS 等文件使用 `biome check --write`，在提交阶段同时覆盖 lint 与格式化修复。
- 统一测试颜色环境，避免因终端颜色变量差异导致的测试不稳定。
- 明确阶段划分：本变更仅覆盖 V1（pnpm 方案）；V2 再增加 Turborepo 命令与 affected/caching 编排能力。

## Capabilities

### New Capabilities
- `workspace-qa-standardization`: 定义 workspace 子项目统一 QA 脚本契约、提交阶段检查策略与测试颜色环境基线。

### Modified Capabilities
- (none)

## Impact

- 受影响代码：`scripts/node/package.json`、`projects/clis/json-diff-tool/package.json`、`lint-staged.config.js`、相关 `vitest.config.ts`。
- 受影响流程：本地 `pre-commit`、子包 `qa` 执行路径、后续 CI 聚合命令设计。
- 对 Turborepo 的影响：本次不引入 Turbo 配置，仅输出可在 V2 直接接入的统一脚本接口。
