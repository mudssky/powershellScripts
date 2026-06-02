# database-query 开箱即用体验实现计划

## Checklist

- [x] 更新 `resolveOptionalDatabase()`，允许 `defaultDatabase` / 显式 `--database` 在无 `databases[]` 时生效。
- [x] 新增 `init-config` CLI 子命令和最小配置模板生成。
- [x] 增强 `doctor` 输出与安装参考文档，明确不自动安装，由 agent 自行选择安装方式。
- [x] 更新 `SKILL.md` 与相关 references。
- [x] 增加测试覆盖目标解析、初始化配置和 doctor 文案。
- [x] 运行 build，同步 `scripts/database-query.js`。
- [x] 运行验证命令。

## Validation

- `fnm exec --using 22.16.0 pnpm --dir ai/skills/dev/database-query check`
- `fnm exec --using 22.16.0 pnpm qa`

## Commit Notes

- 不提交 `.trellis/tasks/06-01-database-query-onboarding` 任务 artifact。
- 只提交代码、文档和必要 spec 变更。
