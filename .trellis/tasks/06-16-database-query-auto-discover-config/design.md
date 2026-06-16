# database-query 数据库自动发现配置优化设计

## Architecture

本次改动限定在 `ai/skills/dev/database-query`。保持 `database-query` 为单文件分发的 Node/TypeScript CLI，新增能力挂在现有 `config` 子命令下：

```bash
node scripts/database-query.js config discover-databases --instance <id>
node scripts/database-query.js config discover-databases --instance <id> --write
node scripts/database-query.js config discover-databases --instance <id> --global --write
```

`context`、`exec`、`client`、`config paths`、`config current` 不改变现有行为。数据库发现和写回必须由 `config discover-databases` 显式触发。

## Boundaries

- 支持 PostgreSQL 与 MySQL。
- 不支持 MongoDB、SQLite、Redis、Milvus 的发现写回；这些类型返回清晰错误。
- 只写回 `*.local.json` 本机私有配置，包括项目目录命中的 local JSON 和 XDG 全局 `database-query.local.json`。
- 普通 `*.config.json`、JS、MJS 配置不自动改写。
- 写回前创建同目录可读时间戳 `.bak` 文件。

## CLI Contract

`config discover-databases` 选项：

- `--config <path>`：显式读取配置；未传时按现有默认查找。
- `--instance <id>`：目标实例；多实例且无默认实例时必须提供。
- `--database <name>`：PostgreSQL 发现时使用的连接库。
- `--include <patterns>`：逗号分隔 glob，只保留匹配库名。
- `--exclude <patterns>`：逗号分隔 glob，排除匹配库名。
- `--write`：写回配置；未传时只打印发现结果和写回提示。
- `--global`：强制将读写目标切到 XDG 全局 `database-query.local.json`。
- `--format <text|json>`：沿用现有配置命令输出风格。

默认输出包含：配置路径、实例、数据库类型、连接库、发现库名、过滤后库名、是否写回、备份路径。

## Discovery Flow

1. 解析目标配置文件：
   - 无 `--global` 时读取 `--config` 或当前默认命中的配置。
   - 有 `--global` 时读取 XDG 全局 `database-query.local.json`。
2. 加载配置并解析目标实例。
3. 根据实例类型创建只读发现计划。
4. 调用底层 CLI 执行发现：
   - PostgreSQL 使用 `psql` 查询 `pg_database`，排除 `datistemplate`，不默认排除 `postgres`。
   - MySQL 使用 `mysql` 查询库列表，排除 `information_schema`、`mysql`、`performance_schema`、`sys`。
5. 解析输出为库名数组，去重、排序并应用 include/exclude glob。
6. 未传 `--write` 时只打印结果。
7. 传 `--write` 时，校验配置路径为 `*.local.json`，创建 `.bak`，然后合并写回。

## Merge Contract

写回只修改目标 instance：

- 合并 `databases[]`，以 `name` 为唯一键。
- 已存在的数据库条目保留 `schemas`、`collections`、`defaultSchema`、`defaultCollection` 等附加字段。
- 新发现库写为 `{ "name": "<database>" }`。
- 不覆盖已有 `defaultDatabase`。
- 若实例没有 `defaultDatabase`，且过滤后的发现结果包含本次 PostgreSQL 发现连接库，则写入该连接库为 `defaultDatabase`。
- 不新增或改写密码、token、uri、url 等连接凭据字段。

## Compatibility

现有目标解析逻辑保留：配置只有 `defaultDatabase`、没有 `databases[]` 时，`exec` / `client` 仍可运行。新增发现命令只补齐候选列表，不改变查询命令语义。

`config paths/current` 继续不读取配置内容、不输出密钥。`config discover-databases` 会连接数据库，因此文档必须明确它不是纯元信息命令。

## Trade-offs

默认不写回可以降低误改风险；skill 文档会指导 agent 在明确缺少候选库时使用 `--write`。`--global` 解决项目 local 配置存在时仍要维护 XDG 全局配置的场景。

首版不做 MongoDB，是因为 MongoDB 发现牵涉 database 与 collection 两层结构，且 URI path 可能已经编码默认库；后续可以单独扩展。

## Rollback

每次 `--write` 前都有同目录 `.bak`。回滚方式是用备份文件替换当前 local JSON 配置。未传 `--write` 的预览模式不会修改任何文件。
