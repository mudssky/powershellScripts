# 改进 database-query 配置命令

## Goal

改进 `database-query` CLI 的配置文件可发现性：新增配置相关子命令，让用户和 agent 能直接查看配置查找顺序、全局配置路径与当前命中的配置文件，而不需要误用 `init-config --global` 或阅读源码推断路径。

## Requirements

- `context` 当前默认输出格式为 `text`，显式 `--format json` 时输出完整 JSON。
- 本任务不新增 `context` 低 token 格式；CSV、TSV、compact 等输出应留到后续整体低 token 设计中统一考虑。
- 新增 `config` 子命令，集中承载配置文件相关能力，避免用户为了知道路径而误用 `init-config --global`。
- `config` 子命令至少支持查看默认查找位置、全局配置目录、默认全局本机配置文件路径、当前工作目录下会命中的项目级配置、以及最终会加载的配置文件。
- 改进底层客户端诊断：在 WSL 场景下，`doctor` 应能识别 PATH 中可用的 Windows `.exe` 客户端，例如 `psql.exe`、`mongosh.exe`，并区分原生命令缺失与 Windows 侧客户端可用。
- 关系型 `exec` / `client --print-command` 的执行计划应与 `doctor` 使用一致的客户端解析：优先原生命令，缺失时才使用 Windows `.exe`。
- SQLite 的 SQL 执行只依赖 instance `path`，不应因为没有 database 配置而报错。
- 新能力不得输出真实密码、token、完整 URI、连接串或其他敏感值。
- 保持现有命令兼容：`context` 默认格式仍为 `text`，`context --format json` 仍可被现有 agent 解析，`init-config --global` 行为不变。
- 更新 tests 与 skill 文档，说明新格式和配置命令。

## Acceptance Criteria

- [ ] `database-query context` 默认仍输出 `text`。
- [ ] `database-query context --format json` 输出结构与敏感信息脱敏行为保持兼容。
- [ ] `database-query config paths` 或等价命令能输出配置查找顺序、全局配置目录和默认全局配置文件路径。
- [ ] `database-query config current` 或等价命令能输出未传 `--config` 时当前会加载的配置文件；不存在配置时给出可操作提示。
- [ ] `database-query doctor` 在 WSL/PATH 中存在 `psql.exe` 但不存在 `psql` 时，报告为 Windows 客户端可用，而不是简单 missing。
- [ ] `database-query doctor` 对确实不存在的客户端仍报告 missing，并保留安装提示。
- [ ] `database-query exec` 能通过全局配置执行 MySQL 与 PostgreSQL 的最小只读查询。
- [ ] `database-query exec` 能对仅配置 `path` 的 SQLite 实例执行最小只读查询。
- [ ] 所有新增输出均不泄漏真实密钥。
- [ ] `pnpm --dir ai/skills/dev/database-query check` 通过。

## Out Of Scope

- 新增 `context --format csv`、`context --format tsv`、`context --format compact` 或其他低 token 格式。
- 对 `context --format json` 做字段裁剪或结构变更。
- 设计全仓库或所有 agent skills 的统一低 token 输出规范。
- 新增 Python、Java 等数据库驱动 fallback 执行路径。

## Future Work

- 单独规划 database-query 的整体低 token 设计，统一考虑 `context`、执行计划、doctor、config 等输出的 agent 消耗与可解析性。
- 单独规划执行路径是否自动使用 Windows `.exe` 客户端；本任务优先改进诊断准确性，避免误报本机完全缺少客户端。

## Notes

- 现有代码位置：
  - `ai/skills/dev/database-query/src/cli.ts`
  - `ai/skills/dev/database-query/src/config.ts`
  - `ai/skills/dev/database-query/src/types.ts`
  - `ai/skills/dev/database-query/tests/check-sql.test.ts`
- 现有文档位置：
  - `ai/skills/dev/database-query/SKILL.md`
  - `ai/skills/dev/database-query/references/skill-installation.md`
