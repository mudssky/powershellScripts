# 数据库查询技能

## Goal

在 `ai/skills/dev/` 下新增一个跨平台数据库查询 skill，帮助 agent 安全地配置、连接和查询多个数据库实例与多个库，并将该 skill 纳入 `ai/skills/skills.config.json` 的默认安装配置。

该 skill 的主要用户价值是：当用户要求跨库查询、连接数据库、排查数据、写临时查询或生成安全的数据库访问流程时，agent 有一套可复用的工作规范，避免泄露凭据、误操作生产数据或把不同数据库的连接方式混在一起。

## Confirmed Facts

- 本地开发 skill 目录规范为 `ai/skills/dev/<skill-name>/SKILL.md`，可按需添加 `references/`、`examples/`、`scripts/`。
- `SKILL.md` frontmatter 必须包含 `name` 与 `description`，名称使用小写短横线并与目录名一致。
- `ai/skills/skills.config.json` 默认只安装显式列出的本地 skill；`IncludeDevAll` 只是临时同步全部 `dev/` skill。
- 当前 `ai/skills/dev/api-example-test-writer` 已有 `SKILL.md`、`references/`、`examples/`、`agents/`，但尚未列入 `skills.config.json`。
- 安装脚本支持本地 skill 配置：`source: "./dev/<skill-name>"` 与 `sourceType: "local"`。
- 新 skill 名称暂定并推荐保留为 `database-query`，目录与 frontmatter `name` 保持一致；该名称强调“查询/只读优先”的安全边界，比 `database-access`、`database-client` 等泛化名称更不容易暗示任意管理能力。
- 非关系型执行方式确定采用方案 A：MongoDB/Redis/Milvus 进入 `database-query exec`，但只开放明确枚举的只读动作，不提供任意命令透传。
- 配置格式需要从 YAML 优先转向 JSON/JS/TS 配置模型；密钥可以放在本机私有配置中，也可以通过环境变量读取。
- 配置字段采用统一字段名和值解析，不再拆出 `passwordEnv`、`uriEnv`、`urlEnv` 等双字段；JSON 使用 `"${env:NAME}"` 占位符，JS/MJS 直接使用 `process.env` 或模板字符串。
- TS 配置首版不作为安装态直接运行能力；提供类型定义和 `// @ts-check` 的 JS/MJS 示例，TS 配置如需使用应由用户自行编译为 JS。

## Requirements

- 新增数据库查询 skill：`ai/skills/dev/database-query/SKILL.md`。
- skill 主要内容使用中文，符合仓库对 skill 文档的语言要求。
- 支持多个实例配置与多个库查询的工作流程，包括连接选择、只读优先、凭据来源、查询前确认上下文、查询结果脱敏与记录命令。
- 配置模型必须区分“数据库实例/服务端/集群”和“实例下的数据库名、schema、集合或 collection”，不能只用扁平环境变量表达多实例。
- 第一阶段重点支持 PostgreSQL、MySQL、SQLite、MongoDB。
- Redis 与 Milvus 做简单支持，主要覆盖连接检查、只读/检索类命令、基础排障与安全边界。
- 第一版不实现完整跨数据库抽象层；不同数据库继续使用各自官方或常见 CLI/SDK 作为真实后端。
- 统一 CLI 只提供上下文发现、SQL guard、受控执行包装和凭据桥接，避免 agent 重复解析配置与密钥，但不承诺覆盖所有数据库能力。
- 关系型数据库可以统一查询纪律、只读 SQL 模板、分页限制、事务回滚模式和结果导出边界，但不强行抽象成同一个数据库驱动。
- 为关系型 SQL 提供执行前安全检查子命令，定位为轻量静态 guardrail；该能力应作为统一 CLI 的 `check-sql` 子命令提供。
- 需求补强：只提供 SQL guard 的 CLI 对实际使用偏单一。skill 应继续提供工具安装、客户端选择、连接参数解析和底层 CLI 调用说明，避免 agent 每次临时推理数据库连接命令。
- 需求补强：相比只封装 `query`，更通用的形态是提供 `exec` 执行包装器：读取 database-query 配置、解析目标实例/数据库/集合、按数据库类型执行受控动作，并在关系型 SQL 执行前自动运行 SQL guard。
- 需求补强：执行包装器若实现，第一阶段应覆盖 PostgreSQL、MySQL、SQLite 的 SQL 执行，以及 MongoDB/Redis/Milvus 的少量只读动作；复杂交互、schema 深查、导出、写入、管理操作仍由 agent 按文档直接使用底层官方 CLI/SDK。
- 需求补强：执行包装器必须以安全和可审计为边界，不做长期连接池、不缓存凭据、不把真实密码打印到 stdout/stderr，不绕过 SQL guard，不隐式提升到 `maintenance`、`admin` 或 `yolo`。
- 需求补强：源码和构建产物应收敛为单 CLI 入口 `scripts/database-query.js`，通过子命令提供 `check-sql`、`doctor`、`exec`，避免单独打包 `check-sql.js` 增加安装态心智负担。
- 需求补强：不提供独立 `print-command` 子命令；命令预览能力收敛到 `exec --verbose` 与 `exec --print-command`。`--verbose` 在真实执行前自动打印脱敏目标、guard 摘要和底层命令/SDK 动作；`--print-command` 只打印脱敏执行计划并退出，不连接数据库、不执行动作。
- 需求补强：agent 的第一步应能从配置文件一次性获取数据库上下文。统一 CLI 需要提供 `context` 子命令，读取配置并输出脱敏实例清单、数据库/schema/collection 结构、默认策略、允许动作和密钥可用性状态，便于 agent 在用户说“用哪个库/哪个表查”时直接定位目标上下文。
- 需求补强：复杂参数或交互式排障仍可能需要底层 CLI。统一 CLI 应提供一个凭据桥接子命令，推荐命名为 `client`：它只负责从配置解析连接参数与密钥、注入官方客户端所需环境变量/参数、打印脱敏预览并启动对应底层客户端；不承诺做 SQL guard、不解析任意复杂命令语义，也不能绕过用户确认高风险操作。
- 需求补强：`--instance` 不应成为每次调用的硬性负担。`exec`、`client` 和可聚焦的 `context` 应支持目标自动解析：显式 `--instance` 优先，其次使用 `defaults.defaultInstance`，再其次当配置中只有一个实例时自动选中；仍有多个候选且无默认值时才以非零退出码提示候选列表。`--database`、`--collection` 等下级目标也采用同样的“显式 > 默认 > 单候选 > 报错”规则。
- 需求补强：`doctor` 子命令应具备工具发现/安装提示能力，例如检查 `psql`、`mysql`、`sqlite3`、`mongosh`、`redis-cli` 是否存在，并给出跨平台安装建议或项目内安装策略；安装命令本身不应自动执行。
- 需求补强：配置文件应承载默认策略，例如默认 `limit`、最大 `limit`、SQL guard 默认权限层级、允许的动作集合、默认输出格式、脱敏字段列表等，避免这些策略散落在命令行参数或文档中。
- 需求补强：配置字段需要有明确映射规则，说明 `host`、`port`、`username`、`password`、`uri`、`url`、`path`、`defaultDatabase`、`databases[].name` 如何转成各底层工具的参数或环境变量。
- 需求补强：凭据字段统一使用真实字段名，例如 `password`、`uri`、`url`，不再额外拆出 `passwordEnv`、`uriEnv`、`urlEnv` 等双字段。JS/MJS 配置可直接用模板字符串或 `process.env.DB_PASSWORD` 读取环境变量；JSON 配置支持轻量占位符字符串，例如 `"${env:DB_PASSWORD}"`。
- 需求补强：密钥可以直接写在被忽略的本机私有配置中；可提交模板只能使用占位符、假值或 `"${env:NAME}"` 引用。所有命令预览、日志、错误输出都必须脱敏。
- 需求补强：配置格式优先支持 JSON 与 JS/MJS。JSON 适合可提交模板和静态配置；JS/MJS 适合读取 `process.env`、复用常量、使用模板字符串和写注释。TS 配置更适合开发体验，但安装态不能默认依赖 `tsx` 或 TypeScript loader；首版可提供类型定义和 `// @ts-check` 的 JS 配置示例，TS 配置作为后续增强或要求用户自行编译为 JS。
- 需求补强：Milvus 没有足够通用的官方 CLI 体验时，应在 `exec` 中用官方 Node.js SDK 封装少量只读能力，例如列 collection、查看 collection/schema、按过滤表达式 query、受 limit 限制的 search；写入、建索引、删 collection 等不纳入首版。
- SQL 安全检查脚本应优先覆盖 PostgreSQL、MySQL、SQLite 的通用风险：多语句、DDL、DML、危险函数/命令、无 `LIMIT` 的查询、大范围导出、事务与锁相关语句等。
- SQL 安全检查脚本不能替代数据库权限、只读账号、人工确认和小结果集策略；静态检查通过也不代表 SQL 一定安全。
- SQL 安全检查脚本默认采用阻断模式：高风险 SQL 直接失败，普通风险输出警告并要求补充限制或确认。
- SQL 安全检查脚本应支持可配置权限层级，例如 `readonly`、`maintenance`、`admin`、`yolo` 或同等语义，用于决定哪些语句类别允许通过。
- `yolo` 权限层级表示用户显式接管风险的越权模式，不能作为默认值，也不能由模糊自然语言请求隐式启用。
- `yolo` 只跳过静态 SQL guard 的阻断，不代表 agent 可以自动执行危险操作；写入、删除、DDL、导出等执行动作仍需用户明确确认实例、数据库、操作与影响范围。
- 现成工具选型结论：SQLFluff 可作为可选语法/lint 辅助，但不是权限策略引擎；首版策略阻断建议自写轻量脚本，避免引入重依赖。
- 运行时证据：仓库根目录已有 Node/Vitest/ESM 脚本与测试约定，skill 目录也已有 Node 脚本先例；Python 只有少量脚本，仓库未提供 `pyproject.toml` 或 `uv.lock`，但已有 `uvx ruff` 格式化入口。
- 带脚本的 dev skill 可以采用 TypeScript 源码 + JavaScript 分发产物结构：`SKILL.md`、`package.json`、`tsconfig.json`、`src/`、`scripts/`。
- `scripts/` 中构建后的 JavaScript 是 skill 安装后的直接运行入口，应提交到仓库；`SKILL.md` 不应要求用户先安装依赖或构建源码后才能使用脚本。
- TypeScript 源码用于维护与测试，构建产物用于跨 agent 分发；脚本调用示例应指向 `scripts/*.js`。
- 带 TypeScript 脚本的 skill 应包含测试目录，例如 `tests/`；开发态复用 monorepo 根目录已有的 Vitest 与 TypeScript 依赖。
- 安装态不要求 `src/`、`tests/`、`package.json`、`tsconfig.json` 参与运行；它们可以被复制到 agent skill 目录，但 `SKILL.md` 不能依赖这些文件运行。
- 当前安装器未提供本地 skill 文件裁剪机制；若需要“安装时只复制 `SKILL.md`、`scripts/`、`references/`、`examples/`”，应作为后续安装器增强单独设计。
- 本次不增强 `Install-Skills.ps1` 的本地 skill 文件裁剪能力；规范先要求运行入口只依赖 `scripts/`，即使开发资产被复制也不影响使用。
- 提供可复制的配置模板或示例，必须区分可提交模板与本机私有配置。
- 推荐采用 `database-query.config.json` 或 `database-query.config.mjs` 描述实例、数据库列表和默认策略。
- 本机私有配置使用 `database-query.local.json`、`database-query.local.js` 或 `database-query.local.mjs`；密钥可以直接写入，也可以通过 `"${env:NAME}"` 或 `process.env.NAME` 引用。
- 可提交示例只能使用占位符、假值和 `"${env:NAME}"` 引用；直接密钥只能出现在不提交的本机私有配置中。
- 若实现阶段新增 `database-query.local.*` 私有配置约定，需要同步更新 `.gitignore`，因为当前根 `.gitignore` 尚未忽略这类本地配置。
- 避免把真实密码、token、连接串、生产凭据写入仓库。
- 将新增 skill 加入 `ai/skills/skills.config.json` 默认安装配置。
- 按用户要求，评估并把 `ai/skills/dev/api-example-test-writer` 也加入 `ai/skills/skills.config.json` 默认安装配置。
- 由于属于文档与配置变更，通常不需要为数据库连接行为写单元测试；若修改安装脚本逻辑才需要补充测试。

## Acceptance Criteria

- [ ] `ai/skills/dev/<skill-name>/SKILL.md` 存在，frontmatter 合规，正文为中文。
- [ ] skill 明确触发场景、工作流程、安全边界、凭据管理、跨数据库支持范围。
- [ ] skill 提供多实例/多库配置示例或引用文件，覆盖 PostgreSQL、MySQL、SQLite、MongoDB，并标注 Redis、Milvus 的简单支持范围。
- [ ] 配置示例明确区分 instance、database/schema/collection、默认 limit/策略 与 secret/env 占位符。
- [ ] JSON/JS 配置示例展示 env 引用方式，并明确本机私有配置不得提交。
- [ ] 若使用 `database-query.local.*` 命名私有配置，`.gitignore` 包含对应忽略规则。
- [ ] skill 明确默认只读策略与需要用户确认的危险操作，例如写入、删除、DDL、生产库操作和大结果集导出。
- [ ] skill 明确 PostgreSQL、MySQL、SQLite 共享关系型查询流程，同时保留各自 CLI 差异。
- [ ] skill 提供执行 SQL 前运行 `database-query check-sql` 的流程，且说明检查只是辅助防线。
- [ ] skill 明确推荐客户端、工具安装检查方式、跨平台安装提示和“缺工具时不要自动安装”的边界。
- [ ] skill 提供配置字段到 PostgreSQL/MySQL/SQLite/MongoDB/Redis/Milvus 常用工具参数的映射说明。
- [ ] skill 说明常见受控动作是否通过 `database-query exec` 包装执行，以及复杂操作何时退回底层 CLI/SDK。
- [ ] `database-query` 源码和构建产物形成单 CLI 入口：`scripts/database-query.js`。
- [ ] 统一 CLI 必须提供 `context`、`check-sql`、`doctor`、`exec` 子命令，不提供独立 `print-command` 子命令。
- [ ] 统一 CLI 应提供凭据桥接能力，推荐为 `client` 子命令，用于从配置选择目标并启动底层官方客户端，同时保证输出脱敏。
- [ ] `context --format json` 必须输出 agent 可解析的脱敏数据库上下文，包括 instance、type、defaultDatabase、databases、schemas/collections、defaults、allowedActions 和 secretStatus。
- [ ] `exec` 与 `client` 在未传 `--instance` 时必须能使用 `defaults.defaultInstance` 或单实例自动推断目标；多实例无默认值时必须报出可选 instance id。
- [ ] `exec` 与 `client` 在未传 `--database`、`--collection` 等下级目标时，应优先使用实例默认值或单候选自动推断；无法唯一确定时必须报出可选目标。
- [ ] `exec --verbose` 必须在执行前打印脱敏执行计划；`exec --print-command` 必须只打印脱敏执行计划并以零退出码结束。
- [ ] `exec` 必须在执行关系型 SQL 前自动调用 SQL guard，并在 guard 阻断时拒绝执行。
- [ ] `exec` 必须支持从配置文件选择 instance/database/collection，并确保凭据不会出现在日志、错误输出或脱敏命令预览中。
- [ ] `exec` 必须为 MongoDB、Redis、Milvus 只开放明确枚举的只读动作，不接受任意写命令透传。
- [ ] SQL 安全检查脚本至少能识别明显危险 SQL 与缺少结果限制的普通查询。
- [ ] SQL 安全检查脚本支持权限层级配置，并在高风险 SQL 命中时以非零退出码阻断。
- [ ] `yolo` 权限层级必须在文档和脚本输出中明确标注高风险，且需要用户显式指定。
- [ ] `ai/skills/dev` 中形成带 TypeScript 脚本 skill 的目录结构与构建/分发规范。
- [ ] `database-query` 使用 TypeScript 源码维护统一 CLI，并提交构建后的 `scripts/database-query.js` 作为实际调用入口。
- [ ] 带 TypeScript 脚本的 skill 测试复用根目录 Vitest/TypeScript，不在每个 skill 内重复安装测试依赖。
- [ ] 规范明确安装后运行入口只依赖 `SKILL.md` 与 `scripts/`，源码和测试是开发态资产。
- [ ] `ai/skills/skills.config.json` 显式列出新增本地 skill，默认可通过安装脚本安装。
- [ ] `ai/skills/skills.config.json` 显式列出 `api-example-test-writer` 本地 skill。
- [ ] 不提交真实凭据或本机私有连接配置。
- [ ] 如只修改 skill 文档与安装配置，按项目规则可不执行 `pnpm qa`；若触及脚本代码则执行根目录 `pnpm qa`。

## Out of Scope

- 不实现完整数据库 GUI、连接池服务或长期运行的代理服务。
- 不实现统一跨数据库查询执行器。
- 不实现覆盖所有数据库能力的统一执行器；`exec` 只覆盖 PostgreSQL/MySQL/SQLite 的受控 SQL 和 MongoDB/Redis/Milvus 的少量只读动作。
- `client` 凭据桥接不替代 `exec` 的安全检查；当 agent 透传复杂底层 CLI 参数时，必须按底层操作风险重新判断是否需要用户确认。
- SQL 安全检查脚本不做数据库连接、不执行 SQL、不保证语义级安全证明。
- 不默认安装数据库客户端、Docker 服务或云数据库 SDK。
- 不为 Redis/Milvus 提供完整管理能力，第一阶段只做基础连接、查询/检索与安全约束。
- 不提供生产写操作自动化。
- 不在本次增强 `Install-Skills.ps1` 的文件裁剪、构建钩子或本地 skill 打包能力。

## Open Questions

- 无。
