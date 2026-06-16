# database-query 数据库自动发现配置优化实现计划

## Checklist

- [x] 在 `ai/skills/dev/database-query/src/types.ts` 增加发现结果或写回摘要所需类型。
- [x] 在 `ai/skills/dev/database-query/src/config.ts` 暴露或新增配置路径解析、local JSON 写回校验、数据库条目合并辅助函数。
- [x] 在 `ai/skills/dev/database-query/src/planner.ts` 或新模块中实现 PostgreSQL / MySQL 只读发现计划。
- [x] 在 `ai/skills/dev/database-query/src/cli.ts` 扩展 `config discover-databases`：
  - [x] 参数解析：`--instance`、`--database`、`--include`、`--exclude`、`--write`、`--global`、`--format`。
  - [x] 预览输出：不写文件。
  - [x] 写回输出：创建 `.bak`、合并 `databases[]`、必要时补 `defaultDatabase`。
  - [x] 非支持类型、非 `*.local.json`、JS/MJS 配置路径的清晰错误。
- [x] 实现 glob 过滤，覆盖逗号分隔 include/exclude。
- [x] 更新 `ai/skills/dev/database-query/tests/check-sql.test.ts`：
  - [x] PostgreSQL 发现输出解析与模板库排除。
  - [x] MySQL 系统库排除。
  - [x] include/exclude glob。
  - [x] `--write` 合并 local JSON 并保留已有条目附加字段。
  - [x] 写回前创建 `.bak`。
  - [x] 未传 `--write` 不修改配置。
  - [x] JS/MJS 或非 local JSON 拒绝写回。
  - [x] 不支持数据库类型返回清晰错误。
- [x] 更新 `ai/skills/dev/database-query/SKILL.md` 与相关 reference 文档，说明 agent 工作流：先 `context`，缺库时 `config discover-databases --write`，再重新 `context`。
- [x] 运行构建，同步 `ai/skills/dev/database-query/scripts/database-query.js`。
- [x] 检查是否需要同步安装副本：
  - [x] `/home/mudssky/.agents/skills/database-query`
  - [x] `/home/mudssky/.codex/skills/database-query`

## Validation

```bash
pnpm --dir ai/skills/dev/database-query check
pnpm qa
```

已执行并通过：

- `pnpm --dir ai/skills/dev/database-query check`
- `pnpm qa`
- `node /home/mudssky/.agents/skills/database-query/scripts/database-query.js config discover-databases --help`
- `node /home/mudssky/.codex/skills/database-query/scripts/database-query.js config discover-databases --help`

如果实现期间触碰 pwsh 相关路径，再按项目规则补跑 `pnpm test:pwsh:all`；当前计划不触碰 pwsh。

## Risky Files

- `ai/skills/dev/database-query/src/cli.ts`：现有 CLI 参数兼容性。
- `ai/skills/dev/database-query/src/config.ts`：配置查找和目标解析合同。
- `ai/skills/dev/database-query/scripts/database-query.js`：构建产物必须和源码同步。
- XDG 全局 local 配置：真实写回验证前必须确认会创建 `.bak`，避免破坏当前可用配置。

## Rollback Points

- 代码回滚：还原 `ai/skills/dev/database-query` 下源码、文档、测试和构建产物。
- 配置回滚：用 `.bak` 文件替换被 `--write` 修改的 `*.local.json`。
