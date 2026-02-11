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

- [ ] 4.1 设计 V2 `turbo run qa` 命令映射与 affected 基线策略（`origin/master`）
- [ ] 4.2 规划 `turbo.json` 任务图（`qa`、`check`、`test:fast`）与缓存边界
- [ ] 4.3 评估并记录 V1（pnpm）与 V2（turbo）在 CI 耗时上的对比指标
