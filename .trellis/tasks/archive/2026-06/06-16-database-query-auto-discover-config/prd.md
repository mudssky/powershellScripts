# database-query 数据库自动发现配置优化

## Goal

降低 `database-query` skill 的初次配置成本：用户只需要配置可连接的数据库实例和一个可用默认库，agent 在发现 `context` 中缺少候选数据库列表时，可以通过安全的只读发现命令一次性枚举该实例下的数据库，并将结果写回本机配置，供后续查询选择目标库。

## Confirmed Facts

- `database-query` 当前配置查找顺序是项目目录优先、XDG 用户级全局目录兜底，当前环境命中 `/home/mudssky/.config/database-query/database-query.local.json`。
- 当前配置已经是 JSON local 配置，适合机器安全地做结构化读写；JS/MJS 配置也被支持，但不能直接无损回写。
- 现有 `resolveTarget()` 已支持关系型实例在只有 `defaultDatabase`、没有 `databases[]` 时执行 `exec` / `client`。
- 现有 `context --format json` 会输出脱敏实例、默认库和 `databases[]`，但没有自动发现或写回候选数据库的能力。
- 当前 skill 已有 `doctor`、`config paths`、`config current`、`init-config`、`exec`、`client` 等 CLI，测试集中在 `ai/skills/dev/database-query/tests/check-sql.test.ts`。
- PostgreSQL / MySQL 客户端参考已经把列库命令记录为只读排障动作：PostgreSQL 可从系统目录查询库名，MySQL 可执行 `show databases;`。
- 项目规范要求修改 `*.local.*`、`.env.local`、`*.local.yaml/json/toml` 等本机配置前，在同目录创建带可读时间戳并以 `.bak` 结尾的备份文件。

## Requirements

- 当某个关系型实例没有配置 `databases[]` 或候选库明显不足时，提供一个明确的 CLI 能力发现该实例下的数据库名称。
- 首版发现范围限定为 PostgreSQL 与 MySQL；MongoDB 的 database / collection 发现暂不纳入本次。
- 发现动作必须只读、脱敏，不输出密码、token、完整连接串或生产凭据。
- PostgreSQL 发现连接优先使用命令行 `--database`，其次使用实例 `defaultDatabase`，都没有时使用常见维护库 `postgres`；MySQL 发现不要求预先选择数据库。
- PostgreSQL 默认排除模板库，但不默认排除 `postgres` 维护库；如需隐藏可通过 `--exclude postgres` 控制。
- 发现结果应可写回本机配置文件，避免用户手工补齐所有数据库。
- 写回发现结果时不修改已有 `defaultDatabase`；若原配置没有 `defaultDatabase`，且发现结果包含本次发现连接库，则将该连接库写为 `defaultDatabase`。
- 默认写回发现到的全部非系统库，并提供 include/exclude 类筛选选项，便于实例内数据库过多时控制配置体积。
- include/exclude 筛选支持逗号分隔的 glob 通配符，例如 `app*,reporting` 或 `*_bak,tmp_*`。
- 写回时保留已有 `defaultDatabase`、实例连接字段和已有数据库条目的 schema/collection 等附加信息。
- 写回只应默认支持可安全结构化修改的 JSON 配置；遇到 JS/MJS 配置时给出清晰提示，避免破坏用户手写逻辑。
- `--write` 只允许写入 `*.local.json` 本机私有 JSON 配置，包括项目目录 local 配置和 XDG 全局 local 配置；普通 `*.config.json`、JS、MJS 配置不自动写回。
- 写回项目目录或 XDG 全局 `database-query.local.json` 等本机配置前，必须先创建同目录 `.bak` 备份文件。
- 写回默认修改当前配置查找规则命中的 `*.local.json`；传入 `--global` 时强制写入 XDG 全局 `database-query.local.json`。
- 发现/写回必须由显式命令触发，`context` 保持只读、快速、无连接数据库或修改配置的副作用。
- 现有 `context`、`exec`、`client`、`config current` 等命令兼容性保持不变。
- 发现入口放在现有 `config` 子命令下，命令形态为 `config discover-databases`，避免配置相关能力分散到多个顶层入口。
- `config discover-databases` 默认只打印发现结果；只有显式传入 `--write` 时才写回配置。
- 文档和 skill 工作流程要指导 agent：先读 `context`，缺少候选库时运行发现/写回，再重新读取 `context`。

## Acceptance Criteria

- [ ] PostgreSQL 实例可通过 CLI 发现数据库列表，发现 SQL 只查询系统目录并排除模板库或系统维护库。
- [ ] PostgreSQL 实例没有 `defaultDatabase` 时，发现命令默认尝试连接 `postgres`；传入 `--database` 时使用指定连接库。
- [ ] PostgreSQL 发现结果默认包含 `postgres` 维护库，排除模板库。
- [ ] MySQL 实例可通过 CLI 发现数据库列表，并排除常见系统库。
- [ ] 对 MongoDB、SQLite、Redis、Milvus 实例运行发现命令时返回清晰的不支持提示。
- [ ] JSON 配置写回会合并数据库候选，不覆盖已有条目的附加字段，不写入任何新增密钥。
- [ ] 写回不会覆盖已有 `defaultDatabase`；无默认库且发现结果包含连接库时，才补写该默认库。
- [ ] 写回本机 JSON 配置前，会创建同目录时间戳 `.bak` 文件。
- [ ] `config discover-databases` 能在现有 `config paths/current` 之外提供数据库候选发现能力。
- [ ] 默认写回全部非系统库；传入筛选选项时只写回匹配的库。
- [ ] `--include` / `--exclude` 支持逗号分隔的 glob 通配符。
- [ ] 不传 `--write` 时，`config discover-databases` 只输出发现结果和写回提示，不修改配置文件。
- [ ] JS/MJS 配置不被自动改写，CLI 返回可操作提示。
- [ ] `--write` 遇到非 `*.local.json` 配置时拒绝写入，并提示改用本机私有 JSON 配置。
- [ ] 当前命中项目 local JSON 时默认写项目配置；传入 `--global` 时写 XDG 全局 local JSON。
- [ ] `context` 不会因为缺少 `databases[]` 而连接数据库或写配置。
- [ ] 发现失败时给出底层客户端、连接或权限相关的清晰错误，不留下半写入配置。
- [ ] `context --format json` 在写回后能看到新增数据库候选。
- [ ] 自动化测试覆盖发现结果解析、JSON 合并写回、JS/MJS 拒绝写回和现有命令兼容。
- [ ] `pnpm --dir ai/skills/dev/database-query check` 与根目录 `pnpm qa` 通过。

## Notes

- 本任务是复杂任务，需要补充 `design.md` 与 `implement.md` 后再进入实现。
- 运行时安装副本可能存在于 `~/.agents/skills/database-query` 与 `~/.codex/skills/database-query`，实现完成后需要考虑同步与验证。

## Open Questions

- 无。
