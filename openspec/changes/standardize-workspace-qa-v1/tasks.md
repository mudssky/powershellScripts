## 1. 统一子包 QA 脚本契约

- [x] 1.1 在 `scripts/node` 增加并对齐 `test:fast`、`check`、`check:fix`、`qa` 脚本
- [x] 1.2 在 `projects/clis/json-diff-tool` 增加并对齐 `test:fast`、`check`、`check:fix`、`qa` 脚本
- [x] 1.3 为历史脚本名保留兼容映射（如 `biome:fixAll`、`biome:check`）

## 2. 提交阶段检查策略收敛

- [x] 2.1 将 `lint-staged` 中 JS/TS/CSS/HTML/JSON 规则统一为 `biome check --write`
- [x] 2.2 确认 `pre-commit` 继续使用 `pnpm lint-staged` 触发提交前收敛

## 3. 测试环境一致性

- [x] 3.1 在 `scripts/node` 的 `vitest.config.ts` 统一颜色环境变量
- [x] 3.2 在 `json-diff-tool` 的 `vitest.config.ts` 统一颜色环境变量
- [x] 3.3 验证默认环境下 `pnpm -C <pkg> run qa` 可稳定执行

## 4. V2 Turbo 预留与后续计划

- [ ] 4.1 新增 Turbo 命令族（方案 A），保留原 `qa*` 命令不变
  - [ ] 4.1.1 在根 `package.json` 增加 `turbo:qa`、`turbo:qa:all`、`turbo:qa:verbose`、`turbo:qa:all:verbose`
  - [ ] 4.1.2 新增 Turbo 编排入口（如 `scripts/qa-turbo.mjs`），对齐 `changed/all/verbose` 语义
  - [ ] 4.1.3 在 `changed` 模式中映射 `QA_BASE_REF -> TURBO_SCM_BASE`，默认 `origin/master`
  - [ ] 4.1.4 维持 root `qa:pwsh` 既有路径探测与执行逻辑，不并入 Turbo Root Task
- [ ] 4.2 规划并落地 `turbo.json` 任务图与缓存边界
  - [ ] 4.2.1 定义 `qa`、`check`、`test:fast`、`typecheck:fast` 任务
  - [ ] 4.2.2 首版采用保守缓存配置（`outputs: []`），优先保证语义一致
  - [ ] 4.2.3 明确后续可演进项：`outputs` 细化与远程缓存接入时机
- [ ] 4.3 评估并记录 V1（pnpm）与 V2（turbo）在 CI 耗时上的对比指标
  - [ ] 4.3.1 采集 `cold(all)`、`warm(all)`、`changed(PR)` 三组耗时
  - [ ] 4.3.2 记录缓存命中率、最长耗时包、失败定位可读性
  - [ ] 4.3.3 CI 补充 affected 前置条件（完整 Git 历史，如 `fetch-depth: 0`）
