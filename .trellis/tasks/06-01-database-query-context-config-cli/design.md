# 改进 database-query 配置命令 Design

## Architecture And Boundaries

`database-query` 是 skill 内独立 Node CLI。改动边界限定在 `ai/skills/dev/database-query`：

- CLI 定义与输出格式在 `src/cli.ts`。
- 配置查找、路径解析与上下文快照在 `src/config.ts`。
- CLI 行为测试在 `tests/check-sql.test.ts`。
- 使用说明在 `SKILL.md` 与 `references/skill-installation.md`。

不改数据库连接、SQL guard、`context` 输出格式，也不改变已有配置文件查找优先级。底层客户端改动包含诊断与执行计划解析：让 `doctor` 更准确识别当前环境中可用的原生命令与 WSL 可调用的 Windows `.exe`，并让 `exec` / `client --print-command` 使用同一解析结果。

## Data Flow And Contracts

`context` 继续走现有流程，保持兼容：

1. `loadConfig(options.config)` 加载显式或默认配置。
2. `createContextSnapshot(loaded, options.instance)` 生成脱敏上下文。
3. 根据 `--format text|json` 输出。

`config` 子命令应只处理配置元信息，不读取或展示真实密钥值。建议命令形态：

- `config paths`：输出默认查找目录、文件名顺序、全局目录与默认全局 local 文件路径。
- `config current [--config <path>] [--format text|json]`：输出当前会使用的配置路径；显式路径优先。未找到时返回非零退出码并提示创建位置。

如实现复杂度更低，也可先实现 `config` 单命令加 `--paths` / `--current`，但子命令更符合可扩展性。

## Compatibility

- `context` 默认格式保持 `text`，避免破坏人的使用习惯和现有测试预期。
- `json` 输出结构不改字段名，避免破坏 agent 依赖。
- 新命令只新增能力，不替换 `init-config --global`。
- 低 token 输出不在本任务中实现，避免提前固定局部格式。
- `doctor` 输出可新增状态细节，例如 `ok (native)`、`ok (windows-exe)`、`missing`；旧语义中的 missing 继续表示当前无法找到可调用客户端。

## Client Tool Diagnosis

当前 `doctor` 只执行无后缀命令，例如 `psql --version`。在 WSL 中，如果 Windows 侧 PostgreSQL 安装目录已进入 PATH，实际可调用命令可能是 `psql.exe`，此时 `psql` 报 `ENOENT`，但 `psql.exe` 可用。

建议新增统一工具探测函数：

1. 优先探测原生命令：`psql`、`mysql`、`mongosh`、`redis-cli`。
2. 原生命令缺失时，探测 Windows 可执行文件：`psql.exe`、`mysql.exe`、`mongosh.exe`、`redis-cli.exe`。
3. 输出工具状态、解析到的实际命令名、来源类型和版本首行。
4. `doctor` 基于该探测结果决定是否展示安装提示。

执行路径也使用同一探测规则，但仍优先原生命令。若用户安装了 Linux 原生 `psql` / `mysql` / `sqlite3`，执行计划应展示并调用原生命令；只有原生命令缺失时才使用 `.exe`。

## Rollback

若 `config` 子命令命名或输出形态不合适，可回滚 CLI 新增命令；配置加载与查询执行路径不应受影响。
