# 数据库查询 Skill 技术设计

## Architecture and Boundaries

本次变更拆成两层：

1. `ai/skills/dev` 开发规范层：定义普通 skill 与带 TypeScript 脚本 skill 的目录结构、构建产物、测试边界和安装态运行契约。
2. `database-query` skill 层：提供数据库查询工作流、JSON/JS 配置模板、SQL 执行前 guard 子命令和默认安装配置。

`database-query` 不实现完整跨数据库执行器。关系型数据库继续以 `psql`、`mysql`、`sqlite3` 为真实执行后端；MongoDB、Redis、Milvus 使用各自 CLI/SDK。skill 规定配置、确认、工具检查、参数映射、安全检查和输出处理流程。

为了提升常见查询易用性，源码和构建产物收敛为单 CLI 多子命令：

- `scripts/database-query.js context`：读取配置，输出脱敏后的实例、数据库、schema/collection、默认策略和允许动作，作为 agent 查询前的第一步上下文发现。
- `scripts/database-query.js check-sql`：仅做静态 SQL 安全检查，不连接数据库。
- `scripts/database-query.js doctor`：检查推荐客户端和 SDK 是否可用，输出缺失工具和安装提示，不自动安装。
- `scripts/database-query.js exec`：按数据库类型执行受控动作；关系型 SQL 执行前自动调用 SQL guard，再调用底层 CLI。
- `scripts/database-query.js client`：从配置解析连接参数与密钥，启动官方底层客户端或打印脱敏启动计划，供复杂参数、交互式排障或 `exec` 未覆盖的只读操作使用。

命令预览不单独做成子命令，避免 CLI 入口膨胀。`exec --verbose` 在真实执行前打印脱敏执行计划，`exec --print-command` 只打印相同执行计划并退出。

复杂交互、schema 深查、导出、写入和管理操作仍退回底层 CLI/SDK，由 agent 按文档和安全边界执行。`client` 只解决“从配置安全取连接参数和注入密钥”的重复工作，不替代 `exec` 的受控动作策略。

## Skill Directory Contract

普通文档型 skill：

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  references/
  examples/
```

带 TypeScript 脚本的 skill：

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  package.json
  tsconfig.json
  src/
    <script>.ts
  tests/
    <script>.test.ts
  scripts/
    <script>.js
```

开发态复用根目录 Node/Vitest/TypeScript/Biome 依赖。安装态以 `SKILL.md` 和 `scripts/*.js` 为运行入口，不要求用户安装依赖或构建源码。构建后的脚本默认保持单文件、未压缩和现代 Node.js 输出；TypeScript CLI 推荐使用 `cac`，极简脚本可使用 Node 内置 `node:util` 的 `parseArgs`。

当前不改 `Install-Skills.ps1` 的复制行为。若 `src/`、`tests/`、`package.json` 被复制到 agent skill 目录，也必须只是附带资产，不能成为运行前提。

## Data Flow and Contracts

### Database Query Config

连接清单和默认策略使用 `database-query.config.json` 或 `database-query.config.mjs` 表达。JSON 适合可提交模板和静态配置；JS/MJS 适合读取 `process.env`、复用常量和写注释。TS 配置可提供类型定义辅助开发，但安装态不能默认依赖 `tsx` 或 TypeScript loader；首版不把 `.ts` 配置作为必需运行态能力。

配置需要表达实例、数据库和命名空间关系：

- `instances[].id`：实例别名。
- `instances[].type`：`postgres`、`mysql`、`sqlite`、`mongodb`、`redis`、`milvus`。
- `instances[].databases[]`：实例下的库；关系型可继续列 `schemas`，MongoDB 可列 `collections`。
- `defaults`：默认策略，例如 `defaultInstance`、`limit`、`maxLimit`、`permissionLevel`、`outputFormat`、`redactFields`、各数据库允许动作。
- `instances[].defaultDatabase`：实例内默认数据库；当实例只有一个 `databases[]` 时可以不写，由 CLI 自动推断。
- `databases[].defaultSchema` / `databases[].defaultCollection`：库内默认 schema 或 collection；当只有一个候选时可以不写，由 CLI 自动推断。
- 凭据字段统一使用真实字段名，例如 `username`、`password`、`uri`、`url`。JS/MJS 配置可以直接使用 `process.env.DB_PASSWORD` 或模板字符串；JSON 配置支持轻量占位符字符串，例如 `"${env:DB_PASSWORD}"`。直接密钥只允许出现在被忽略的本机私有配置中。
- 字段到工具参数的映射必须显式记录：
  - PostgreSQL：`host` -> `-h`，`port` -> `-p`，`username` -> `-U`，database -> `-d`，password -> 子进程 `PGPASSWORD`。
  - MySQL：`host` -> `--host`，`port` -> `--port`，`username` -> `--user`，database -> 位置参数或 `--database`，password -> 子进程 `MYSQL_PWD` 或安全配置文件；命令预览不得显示明文密码。
  - SQLite：`path` -> 数据库文件路径，database 名称通常只用于 `main`/attached database 语义，不作为连接参数。
  - MongoDB：`uri` -> `mongosh` URI，database -> URI path 或 `--eval` 中的 `db.getSiblingDB`。
  - Redis：`url` -> `redis-cli -u`。
  - Milvus：`uri` -> `@zilliz/milvus2-sdk-node` 的 `MilvusClient({ address })` 或等价鉴权参数；首版不依赖外部 Milvus CLI。

可提交模板只允许占位符、假值和 `"${env:NAME}"` 引用。本机私有配置命名为 `database-query.local.json`、`database-query.local.js` 或 `database-query.local.mjs`，必须被 `.gitignore` 忽略。

### Context Discovery

agent 使用该 skill 的第一步应是读取上下文，而不是直接猜实例或手写连接参数：

```bash
node ai/skills/dev/database-query/scripts/database-query.js context --format json
```

`context` 子命令读取同一套配置解析逻辑，输出脱敏信息：

- `instances[].id`、`type`、`environment`、`defaultDatabase`、`readonly`。
- `instances[].databases[].name`、`schemas`、`collections`。
- `defaults.limit`、`defaults.maxLimit`、`defaults.permissionLevel`、`defaults.outputFormat`。
- `allowedActions`：按数据库类型列出 `exec` 允许的动作。
- `secretStatus`：只输出 `present`、`missing`、`notRequired`，不得输出真实字段值。

默认文本输出用于人读；`--format json` 用于 agent 解析。`context --instance <id>` 可聚焦单个实例，`--include-secrets` 不应存在，避免把上下文命令变成泄密入口。

### Target Resolution

为减少人工调用负担，`exec`、`client` 和可聚焦的 `context` 使用同一套目标解析规则：

1. 显式命令行参数优先，例如 `--instance`、`--database`、`--schema`、`--collection`。
2. 其次使用配置默认值，例如 `defaults.defaultInstance`、`instances[].defaultDatabase`、`databases[].defaultSchema`、`databases[].defaultCollection`。
3. 如果当前层级只有一个候选，则自动选中该候选。
4. 如果仍无法唯一确定，命令以非零退出码失败，并输出可选 `id` / database / schema / collection 列表。

`context` 不传目标时默认输出全部上下文；传 `--instance` 或 `--database` 时按上述规则聚焦。`exec` 和 `client` 需要唯一目标，因此不能在多实例无默认值时静默选择第一个实例。

### SQL Guard

SQL guard 是统一 CLI 的子命令，由 TypeScript 源码维护、Rolldown 单文件打包、JavaScript 分发：

```bash
node ai/skills/dev/database-query/scripts/database-query.js check-sql --dialect postgres --level readonly --file query.sql
```

职责：

- 静态分析 SQL 文本，不连接数据库，不执行 SQL。
- 识别多语句、DDL、DML、危险导出、锁、事务、危险函数/命令和缺少结果限制的查询。
- 根据权限层级输出阻断或警告：
  - `readonly`：只允许 `SELECT` / `WITH ... SELECT` / `EXPLAIN SELECT` 类只读查询，要求结果限制。
  - `maintenance`：允许部分维护/检查语句，但默认阻断破坏性 DDL/DML。
  - `admin`：放宽管理语句，但仍阻断极高危行为或要求明确确认。
  - `yolo`：不阻断静态检查命中项，只输出高风险报告；执行危险操作仍需用户显式确认实例、数据库、操作和影响范围。

SQLFluff 可以作为文档中的可选增强，不纳入默认依赖。

### Unified CLI Wrapper

`scripts/database-query.js` 负责 SQL 检查、工具检查、脱敏命令预览和受控执行。建议子命令：

- `context`：读取配置并输出脱敏数据库上下文，作为 agent 查询前的第一步。
- `doctor`：检查 Node.js、`psql`、`mysql`、`sqlite3`、`mongosh`、`redis-cli` 和 Milvus SDK 是否可用，输出安装提示，不自动安装。
- `exec`：执行明确枚举的动作。
- `client`：解析配置并启动底层官方客户端，或用 `--print-command` 只打印脱敏启动计划。

`exec` 支持两个预览相关选项：

- `--verbose`：执行前打印脱敏目标、权限层级、limit、SQL guard 结论和底层命令/SDK 动作摘要，然后继续执行。
- `--print-command`：只打印与 `--verbose` 相同的脱敏执行计划并退出，不连接数据库、不调用底层 CLI/SDK。

`exec` 的数据流为：

1. 读取 `--config` 指向的配置文件，默认查找 `database-query.local.mjs`、`database-query.local.json`、`database-query.config.mjs`、`database-query.config.json` 等常见文件。
2. 使用目标解析规则选择连接目标；未指定 `--instance` 时可使用 `defaults.defaultInstance` 或单实例自动推断，未指定数据库时使用实例 `defaultDatabase` 或单数据库自动推断。
3. 解析直接密钥或 `"${env:NAME}"` 引用，缺失时以非零退出码提示缺少字段或环境变量。
4. 根据实例类型选择受控执行路径：
   - PostgreSQL/MySQL/SQLite：读取 `--sql` 或 `--file`，用同一套 `checkSql` 核心逻辑检查；通过后调用 `psql`、`mysql`、`sqlite3`。
   - MongoDB：只允许枚举动作，例如 `list-collections`、`count`、`find`，底层调用 `mongosh`。
   - Redis：只允许枚举动作，例如 `ping`、`info`、`scan`、`type`、`ttl`、小范围 `get`/`hget`/`lrange`，底层调用 `redis-cli`。
  - Milvus：只允许枚举动作，例如 `list-collections`、`describe-collection`、`query`、受 `limit` 约束的 `search`，底层使用官方 Node.js SDK。
5. guard 或动作策略阻断时拒绝执行；警告时输出风险并遵循权限层级策略。
6. 组装底层 CLI 参数，用 `spawn` 参数数组执行，避免 shell 字符串拼接；Milvus 通过 SDK API 调用。
7. 将密码放入子进程环境变量、客户端安全参数或 SDK config，不打印真实密钥。

`--print-command` 在第 6 步组装出执行计划后停止；`--verbose` 则打印执行计划后继续第 7 步。两者输出都必须使用脱敏后的参数，不得包含明文密码、token 或完整私密连接串。

该包装器只服务高频、低风险、可枚举动作，目标是减少 agent 每次重复解释连接字段、工具参数和 guard 顺序的 token 开销；它不是数据库驱动层或完整跨库抽象层。

### Credential Bridge for Raw Clients

`client` 子命令服务 `exec` 覆盖不到的复杂 CLI 场景，例如 PostgreSQL 的 `\d+` 交互、MySQL 复杂客户端选项、MongoDB 只读排障脚本或 Redis/Milvus 的人工检查。它的职责是：

1. 读取配置，并用统一目标解析规则选择 instance 与可选 database/schema/collection。
2. 解析直接密钥或 `"${env:NAME}"` 引用。
3. 组装底层客户端启动计划，并对命令预览脱敏。
4. 真实启动时将密钥注入子进程环境或安全参数。
5. 支持 `--print-command` 只打印计划，不启动客户端。
6. 可通过 `--` 之后的参数透传到底层 CLI，但必须在文档中提示：透传参数的风险由 agent 依据底层命令语义判断。

首版映射：

- PostgreSQL：`client --instance pg --database app -- --set ON_ERROR_STOP=1` -> `psql`，密码走 `PGPASSWORD`。
- MySQL：`client --instance mysql --database app -- --batch --raw` -> `mysql`，密码走 `MYSQL_PWD` 或安全配置文件。
- SQLite：`client --instance sqlite -- --readonly` -> `sqlite3`，路径来自配置。
- MongoDB：`client --instance mongo --database app -- --quiet` -> `mongosh`，URI 脱敏预览。
- Redis：`client --instance redis -- --scan --pattern user:*` -> `redis-cli -u <redacted>`。
- Milvus：官方 CLI 体验不足，`client` 首版可只打印 SDK 连接摘要或提示使用 `exec` 的 Milvus 只读动作；如后续确定 CLI 再补映射。

`client` 不自动运行 SQL guard，因为它无法可靠理解透传参数和交互式输入；agent 使用它执行 SQL 文件或危险操作前，仍必须先调用 `check-sql` 或要求用户明确确认。

Milvus SDK 作为可选外部运行依赖处理，不打包进 `scripts/database-query.js`，避免显著增大分发脚本。`doctor` 负责提示 `@zilliz/milvus2-sdk-node` 是否可用；执行 Milvus 动作时若 SDK 不存在，CLI 给出明确安装提示。

## Compatibility and Migration Notes

- `.gitignore` 需要新增 `database-query.local.*`，以支撑本机私有配置。
- `ai/skills/skills.config.json` 需要新增本地 skill：
  - `database-query`
  - `api-example-test-writer`
- 因 `skills.config.json` 是安装配置文件，改动不需要单元测试；SQL guard 脚本属于业务逻辑，需要测试。

## Trade-offs

- 使用 TypeScript 源码加提交 `scripts/database-query.js` 会带来构建产物维护成本，但换来安装态零构建和更好的开发态类型安全。
- 新增 `exec` 包装能力会提高常见查询易用性和安全默认值，但会扩大测试范围、凭据处理风险和客户端差异处理成本；因此第一阶段只开放明确枚举的只读/低风险动作。
- 不做安装器裁剪会让开发资产可能被复制到 agent 目录，但避免本次扩大安装器行为与测试范围。
- 自写轻量 SQL guard 不能替代 AST 级 SQL parser，但足以覆盖首版安全策略，避免引入 SQLFluff 等重依赖。

## Operational and Rollback Considerations

- `scripts/*.js` 必须由 `pnpm --dir ai/skills/dev/database-query build` 或等价命令生成，不手工改。
- SQL guard 误报时可用更高权限层级处理，但 `yolo` 只能用户显式指定。
- 回滚时删除 `database-query` 目录、移除 `skills.config.json` 本地 skill 项、撤销 `.gitignore` 本机私有配置规则即可。
