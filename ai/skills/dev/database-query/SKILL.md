---
name: database-query
description: 安全连接和查询多个数据库实例。Use when 用户要求连接数据库、跨实例/跨库查询、排查数据、执行 SQL 前安全检查、查看 PostgreSQL/MySQL/SQLite/MongoDB 数据，或对 Redis/Milvus 做基础只读检查。
---

# 数据库查询

## 使用时机

用于帮助 agent 在多个数据库实例和多个库之间安全查询数据。优先覆盖 PostgreSQL、MySQL、SQLite、MongoDB；Redis 与 Milvus 只做连接检查、只读检索和基础排障。

## 工作流程

1. 先读取上下文，不要猜实例或库名：

   ```bash
   node scripts/database-query.js context --format json
   ```

2. 根据上下文确认目标 instance、database、schema/collection、环境、只读状态、允许动作和密钥状态。关系型实例缺少 `databases[]` 候选时，先用 `config discover-databases` 发现并写回本机 local JSON 配置，再重新读取上下文：

   ```bash
   node scripts/database-query.js config discover-databases --instance local-postgres --write
   node scripts/database-query.js context --format json
   ```

   若当前项目 local 配置存在但需要维护 XDG 全局配置，显式加 `--global`。发现命令默认只预览，只有传 `--write` 才会创建 `.bak` 并写回 `*.local.json`。

3. 常规查询优先使用 `exec`。关系型 SQL 会自动先跑 SQL guard，通过后才调用底层 CLI：

   ```bash
   node scripts/database-query.js exec --sql "select id from users limit 10" --verbose
   ```

4. 复杂参数、交互式排障或 `exec` 未覆盖的只读操作，用 `client` 作为凭据桥接，不要手写密码或完整连接串：

   ```bash
   node scripts/database-query.js client -- --set ON_ERROR_STOP=1
   ```

5. 默认使用 `readonly` 层级。只有用户明确指定实例、数据库、操作和影响范围时，才考虑 `maintenance`、`admin` 或 `yolo`。
6. 关系型查询默认加小结果集限制，例如 `LIMIT 50`。需要导出、大范围扫描、锁表、DDL、写入或删除时，必须先说明风险并等待用户确认。
7. 查询结果输出前做最小化处理：只返回用户需要的字段，避免展示密码、token、密钥、Cookie、身份证、手机号、邮箱等敏感值。
8. 记录最终使用的实例、数据库、查询目的和脱敏命令形态，不记录真实密码、token 或完整生产连接串。

## CLI 命令

- `context`：输出脱敏数据库上下文。agent 第一步应优先使用 `--format json`。
- `check-sql`：只做关系型 SQL 静态安全检查，不连接数据库。
- `doctor`：检查 `psql`、`mysql`、`sqlite3`、`mongosh`、`redis-cli` 等工具是否可用；WSL 场景会在原生命令缺失时识别 PATH 中的 Windows `.exe` 客户端。只给安装提示，不自动安装；agent 根据当前平台、权限和 PATH 自行选择安装方式。
- `config paths`：输出配置文件默认查找顺序、全局配置目录和默认全局本机配置文件路径。
- `config current`：输出当前会使用的配置文件路径；支持 `--config` 与 `--format json`。
- `config discover-databases`：连接 PostgreSQL/MySQL 发现数据库候选；默认只预览，传 `--write` 才写回 `*.local.json`，写前创建同目录 `.bak`。
- `init-config`：生成最小配置模板；常用 `--global` 写入 XDG 用户级配置，`--print` 只打印模板。
- `exec`：执行受控动作。SQL 会自动 guard；MongoDB/Redis/Milvus 只允许配置中的只读动作。
- `client`：凭据桥接。解析配置并启动底层官方 CLI，`--` 后参数透传；它不替代 SQL guard。

`exec --verbose` 会在执行前打印脱敏执行计划；`exec --print-command` 只打印计划不执行。`client --print-command` 只打印底层客户端启动计划。执行计划会优先使用原生命令；WSL 中原生命令缺失但 Windows `.exe` 客户端可用时，会使用 `.exe` 命令。

## 目标解析

`--instance`、`--database`、`--schema`、`--collection` 都不是每次必填。CLI 按以下顺序解析目标：

1. 显式命令行参数。
2. 配置默认值，例如 `defaults.defaultInstance`、`instances[].defaultDatabase`。
3. 单候选自动推断。
4. 多候选且无默认值时报错，并列出可选目标。

多实例环境不要静默选择第一个实例，避免误连生产库。

关系型实例配置了 `defaultDatabase` 时，可以省略 `databases[]`。此时 `exec` / `client` 会直接使用 `defaultDatabase`；用户显式传入 `--database` 时也可以使用未预登记的库名。需要限制候选库、schema 或 collection 时，再配置 `databases[]`。

## 配置文件

未传 `--config` 时，先在当前工作目录查找项目级配置；找不到时，再查找 agent 无关的用户级全局配置目录：

- `$XDG_CONFIG_HOME/database-query/`
- 未设置 `XDG_CONFIG_HOME` 时为 `~/.config/database-query/`

每个目录内的默认文件名顺序：

1. `database-query.local.mjs`
2. `database-query.local.js`
3. `database-query.local.json`
4. `database-query.config.mjs`
5. `database-query.config.js`
6. `database-query.config.json`

显式 `--config` 永远优先于默认查找。JSON 配置使用 `"${env:NAME}"` 引用环境变量；JS/MJS 配置可以直接使用 `process.env.NAME` 或模板字符串。密钥可以直接写在本机私有 `database-query.local.*` 中；项目级真实 local 文件必须被 `.gitignore` 忽略，不要提交，全局 local 文件应放在用户私有配置目录并限制文件权限。

生成最小全局配置模板：

```bash
node scripts/database-query.js config paths
node scripts/database-query.js config current
node scripts/database-query.js config current --format json
node scripts/database-query.js config discover-databases --instance local-postgres
node scripts/database-query.js config discover-databases --instance local-postgres --write
node scripts/database-query.js config discover-databases --global --instance local-postgres --write
node scripts/database-query.js init-config --global
node scripts/database-query.js init-config --global --print
```

`init-config` 默认不覆盖已有文件；需要覆盖时显式传 `--force`。

发现数据库候选时，PostgreSQL 连接库按 `--database`、实例 `defaultDatabase`、`postgres` 的顺序选择；MySQL 不要求预先选择数据库。`--include` / `--exclude` 支持逗号分隔 glob，例如 `app*,reporting` 或 `*_bak,tmp_*`。写回只允许本机私有 `*.local.json`，不会改写 JS/MJS 或可提交 `*.config.json`。

配置字段到工具参数的核心映射：

- PostgreSQL：`host` -> `-h`，`port` -> `-p`，`username` -> `-U`，database -> `-d`，`password` -> `PGPASSWORD`。
- MySQL：`host` -> `--host`，`port` -> `--port`，`username` -> `--user`，database -> `--database`，`password` -> `MYSQL_PWD`。
- SQLite：`path` -> 数据库文件路径。
- MongoDB：`uri` -> `mongosh` URI，database -> URI path。
- Redis：`url` -> `redis-cli -u`。
- Milvus：`address` / `uri` -> Node SDK 连接地址，`token` 作为 SDK 鉴权密钥。

## 权限层级

- `readonly`：默认层级。只允许 `SELECT` / `WITH ... SELECT` / `EXPLAIN SELECT` 等只读查询，并要求结果限制。
- `maintenance`：用于排障和维护检查。允许部分 `EXPLAIN`、`SHOW`、`DESCRIBE`、`PRAGMA` 等语句；写入、删除和破坏性 DDL 默认阻断。
- `admin`：用于明确的管理操作建议。仍要阻断或强提示导出、删库、清表、大范围变更等高风险动作。
- `yolo`：用户显式接管静态 SQL 风险。它只跳过 SQL guard 的阻断，不代表 agent 可以自动执行危险操作。

## 数据库范围

### PostgreSQL / MySQL / SQLite

- 统一遵循只读优先、查询前 guard、结果限制、敏感字段脱敏和危险操作确认。
- 常规 SQL 用 `exec`；复杂客户端参数用 `client`，但执行 SQL 文件前仍要先 `check-sql`。
- 查询结构时优先使用只读元数据语句，例如 `information_schema`、`\dt`、`.tables`、`PRAGMA table_info`。

### MongoDB

- `exec` 默认只做 `list-collections`、`count`、`find`。
- 复杂只读排障可用 `client` 启动 `mongosh`，但不要透传写入、删除或 drop 操作。
- `insert`、`update`、`delete`、`drop`、`aggregate $out/$merge` 必须按高风险操作处理。

### Redis

- `exec` 默认只做 `PING`、`INFO`、`SCAN`、`TYPE`、`TTL`、小范围 `GET/HGET/LRANGE`。
- 禁止自动执行 `FLUSH*`、`DEL`、`EVAL`、`CONFIG SET`、`SHUTDOWN`。

### Milvus

- `exec` 默认只做 collection 列表、schema 查看和小规模 query/search。
- Milvus 首版优先使用 Node SDK 封装只读动作；`client` 只打印 SDK 连接摘要或提示使用 `exec`。
- 删除 collection、批量删除向量、重建索引等属于高风险操作。

## 资源

- SQL guard 规则与命令：`references/sql-guard.md`。
- 底层客户端安装参考：`references/client-installation.md`。
- 底层客户端参考按需读取：
  - PostgreSQL：`references/client-postgresql.md`。
  - MySQL：`references/client-mysql.md`。
  - SQLite：`references/client-sqlite.md`。
  - MongoDB：`references/client-mongodb.md`。
  - Redis：`references/client-redis.md`。
  - Milvus：`references/client-milvus.md`。
- 可提交 JSON 模板：`references/database-query.config.json`。
- JS/MJS 配置示例：`references/database-query.config.mjs`。
- 本机私有配置示例：`references/database-query.local.example.json`。
- SQL 示例：`examples/sql/readonly-safe.sql`、`examples/sql/dangerous-drop.sql`。

## 边界

- 不实现数据库 GUI、连接池服务、完整数据库驱动层或长期运行代理。
- 不默认安装数据库客户端、Docker 服务或云数据库 SDK。
- 不把真实密码、token、连接串、生产凭据写入仓库。
- 不凭猜测选择生产实例、库名、schema 或 collection。
- 不自动执行写入、删除、DDL、大范围导出、锁表、批量更新或生产库高风险操作。
