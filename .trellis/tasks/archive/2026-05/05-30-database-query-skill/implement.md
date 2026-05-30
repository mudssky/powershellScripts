# 数据库查询 Skill 实施计划

## Checklist

1. 更新并应用 skill 开发规范
   - 新增 `.trellis/spec/infra/agent-skill-dev.md`，记录 `ai/skills/dev` TypeScript 脚本型 skill 的可执行规范。
   - 更新 `.trellis/spec/infra/index.md`，让后续开发前能发现该规范。
   - 更新 `ai/skills/SKILL_SPEC.md`，与 Trellis spec 保持一致。
   - 补充带 TypeScript 脚本 skill 的推荐目录结构。
   - 明确 `scripts/` 中的构建后 JS 是提交的分发产物，`SKILL.md` 命令必须指向 `scripts/*.js`。
   - 明确测试目录、根依赖复用、Biome 复用和安装态边界。

2. 更新 `.gitignore`
   - 增加 `*.local.yaml` 与 `*.local.yml`。
   - 增加 `database-query.local.*`。
   - 保持可提交模板不被忽略。

3. 创建 `ai/skills/dev/database-query`
   - `SKILL.md`：中文主体，定义触发场景、工作流、数据库范围、安全边界和资源引用。
   - `references/database-query.config.json`：可提交的多实例连接清单与默认策略模板。
   - `references/database-query.config.mjs`：支持 `process.env`、常量和注释的 JS 配置示例。
   - `references/database-query.local.example.json`：本机私有配置示例，展示直接密钥假值和 `"${env:NAME}"` 引用。
   - `references/sql-guard.md`：SQL guard 权限层级、风险规则和使用示例。
   - `examples/sql/`：安全查询与危险查询示例。

4. 实现统一 CLI
   - `package.json`：使用根目录依赖，提供 `build`、`test`、`check`。
   - `tsconfig.json`：执行 TypeScript 类型检查，不直接生成多文件运行产物。
   - `build.mjs`：使用 Rolldown 打包单文件 `scripts/database-query.js`，不压缩，保持现代 Node.js 可读输出。
   - `src/database-query.ts`：统一 CLI 入口。
   - `src/database-query.ts`：统一 CLI 入口。
   - `src/cli.ts`、`src/config.ts`、`src/planner.ts`、`src/core.ts`：实现多子命令、配置解析、目标解析、执行计划与 SQL guard 核心函数。
   - `tests/check-sql.test.ts`：覆盖 readonly、maintenance、admin、yolo、多语句、DDL/DML、缺少 LIMIT。
   - 构建生成并提交 `scripts/database-query.js`。

4.1 补强连接与执行易用性需求
   - 在 `SKILL.md` 增加推荐工具矩阵：PostgreSQL `psql`、MySQL `mysql`、SQLite `sqlite3`、MongoDB `mongosh`、Redis `redis-cli`、Milvus SDK/CLI 边界。
   - 新增或更新 reference，说明工具安装检查、缺失工具的安装提示、以及不自动安装数据库客户端的边界。
   - 明确配置字段到各底层工具参数和环境变量的映射规则，尤其是密码不得进入命令行字符串或日志。
   - 将默认 `limit`、最大 `limit`、默认权限层级、允许动作集合、输出格式、脱敏字段等策略抽到配置文件。
   - 实现统一目标解析：显式参数优先，其次配置默认值，其次单候选自动推断，多候选无默认值时报出候选列表。
   - 将源码和构建产物调整为单 CLI：`scripts/database-query.js`。
   - 统一 CLI 提供 `context`、`check-sql`、`doctor`、`exec` 子命令。
   - 增加 `context` 子命令：从配置输出脱敏实例/数据库/schema/collection/默认策略/允许动作/密钥状态，支持 `--format json` 供 agent 第一步读取上下文。
   - 增加凭据桥接子命令 `client`：从配置解析连接参数和密钥，启动底层官方 CLI 或用 `--print-command` 打印脱敏启动计划，支持 `--` 之后透传复杂参数。
   - 在 `exec` 上实现 `--verbose` 与 `--print-command`：前者执行前打印脱敏执行计划，后者只打印脱敏执行计划并退出。
   - `database-query exec` 第一阶段覆盖 PostgreSQL/MySQL/SQLite 的受控 SQL 执行：读取配置，选择实例/数据库，自动运行 guard，然后通过底层 CLI 执行。
   - `database-query exec` 为 MongoDB/Redis/Milvus 只开放枚举的只读动作；Milvus 使用可选官方 Node.js SDK 封装基础 collection/query/search 能力，SDK 不打包进分发脚本，由 `doctor` 检查。
   - 若实现 `context`、`client`、`exec`，补充上下文输出脱敏、默认实例解析、单实例自动推断、多候选报错、凭据状态、缺客户端、缺环境变量、guard 阻断、动作不允许、底层 CLI/SDK 非零错误等测试。

5. 更新默认安装配置
   - 在 `ai/skills/skills.config.json` 新增 `database-query` 本地 skill。
   - 在 `ai/skills/skills.config.json` 新增 `api-example-test-writer` 本地 skill。

6. 验证
   - `pnpm --dir ai/skills/dev/database-query build`
   - `pnpm --dir ai/skills/dev/database-query test`
   - `node ai/skills/dev/database-query/scripts/database-query.js check-sql --dialect postgres --level readonly --sql "select * from users limit 10"`
   - `pnpm qa`

## Risky Files and Rollback Points

- `.gitignore`：只增加本机私有配置忽略规则，避免误忽略模板。
- `ai/skills/skills.config.json`：JSON 语法必须保持有效。
- `scripts/database-query.js`：由构建产物生成，不手改。

## Notes

- 本次涉及 TypeScript/Node 脚本与测试，完成后执行根目录 `pnpm qa`。
- 不修改 `Install-Skills.ps1`，避免扩大安装器行为。
- 不提交真实数据库连接信息或密钥。
