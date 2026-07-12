# PostgreSQL Toolkit Design

## Summary

本设计定义一个基于 PowerShell 的 PostgreSQL 命令行工具，目标是在 `scripts/pwsh/devops/` 下提供一套跨平台、可维护、可打包为单文件脚本的数据库运维工具链。

第一版聚焦 4 个高频能力：

- 单库备份
- 备份恢复
- PostgreSQL CLI 工具安装与检测
- 将 CSV 导入已存在的 PostgreSQL 表

实现方式采用“多文件源码 + 构建脚本产出单文件脚本与帮助文档”的结构，兼顾日常维护体验与单文件分发体验。

## Context

当前仓库已经具备两类与本设计直接相关的前提：

- `docs/cheatsheet/database/postgresql/backup-restore.md` 已经沉淀了 PostgreSQL 备份与恢复常见命令，但还没有对应的 PowerShell 自动化工具。
- `scripts/pwsh/devops/` 目录下已有多份带注释帮助、`CmdletBinding`、严格模式和 Pester 测试的运维脚本，说明仓库更偏向“脚本式工具 + 测试覆盖”的组织方式。

用户需求可以收敛为以下几点：

- 工具源码允许拆分在一个目录下的多个文件中维护。
- 最终需要产出一个更接近命令行工具体验的单文件 PowerShell 脚本。
- 支持 Windows、macOS、Linux 三个平台。
- 对外提供 `backup`、`restore`、`install-tools`、`import-csv` 这四个核心子命令。
- 连接信息同时支持连接串、显式参数和 PostgreSQL 标准环境变量。
- CSV 导入只覆盖“导入到已存在表”的场景，不负责自动建表。
- 源码目录中需要包含 `README.md` 与 `.env.example`。
- 打包时除了单文件脚本，还要额外产出一份帮助文档，方便离线查看。

## Goals

- 提供一个跨平台的 PostgreSQL PowerShell CLI。
- 在保持源码可维护的前提下，输出一个单文件脚本产物。
- 统一封装常见 PostgreSQL 备份与恢复流程，减少手工记忆命令。
- 为 PostgreSQL CLI 工具缺失场景提供检测、安装建议和可选自动安装。
- 为 CSV 数据导入提供默认安全、接近 PostgreSQL 官方工具习惯的工作流。
- 提供清晰的 README、示例环境变量文件和独立帮助文档。

## Non-Goals

- 不实现自动建表、列类型推断、主键推断或索引推断。
- 不实现完整数据库迁移框架、schema diff 或数据同步平台能力。
- 不在第一版中覆盖 PostgreSQL 所有 `pg_dump` / `pg_restore` 冷门参数。
- 不依赖真实 PostgreSQL 实例作为日常测试的前置条件。
- 不做图形界面、TUI 或浏览器控制台。

## Constraints

- 源码与产物都必须位于 `scripts/pwsh/devops/` 相关路径下。
- 对外体验应接近通用命令行工具，使用单入口脚本 + 子命令模式。
- 必须兼容 Windows、macOS、Linux 的基础差异，尤其是工具安装路径与包管理器差异。
- 日志和 dry-run 中不能泄露明文密码。
- 所有公共入口和非直观逻辑都需要带清晰注释，符合仓库现有 PowerShell 风格。
- 测试需要适配仓库现有 Pester 体系。

## Chosen Approach

采用“目录化源码实现 + 构建脚本拼装单文件产物”的方案。

工具在开发阶段保持多文件结构，把职责拆分为：

- CLI 入口与帮助输出
- 子命令实现
- 公共连接上下文与参数拼装逻辑
- 平台检测与安装命令生成
- 构建与帮助文档生成

最终通过专用构建脚本按固定顺序拼装源码片段，产出：

- 一个单文件 PowerShell 脚本
- 一份独立 Markdown 帮助文档

该方案比“所有逻辑直接塞进一个脚本”更适合长期维护，也比“先做模块再包薄入口”更贴近当前以单文件 CLI 分发为中心的目标。

## Source Layout

源码建议放在 `scripts/pwsh/devops/postgresql/`，结构如下：

```text
scripts/pwsh/devops/postgresql/
├── README.md
├── .env.example
├── main.ps1
├── build/
│   └── Build-PostgresToolkit.ps1
├── docs/
│   └── help.md
├── core/
│   ├── logging.ps1
│   ├── process.ps1
│   ├── context.ps1
│   ├── connection.ps1
│   ├── formats.ps1
│   └── validation.ps1
├── commands/
│   ├── backup.ps1
│   ├── restore.ps1
│   ├── import-csv.ps1
│   ├── install-tools.ps1
│   └── help.ps1
└── platforms/
    ├── windows.ps1
    ├── macos.ps1
    └── linux.ps1
```

模块边界如下：

- `main.ps1` 只负责参数入口、子命令分发和顶层错误处理。
- `core/` 负责连接解析、命令调用、日志、输入校验与格式识别。
- `commands/` 负责把用户输入翻译成 PostgreSQL 官方 CLI 参数。
- `platforms/` 负责输出或执行平台相关安装命令。
- `build/` 只负责编译式拼装，不承载业务逻辑。
- `docs/help.md` 作为帮助文档源文件，同时服务于独立帮助文档产物和脚本内嵌帮助文本。

## Build Outputs

构建脚本 `scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1` 生成以下产物：

- `scripts/pwsh/devops/Postgres-Toolkit.ps1`
- `scripts/pwsh/devops/Postgres-Toolkit.Help.md`

构建行为建议如下：

1. 按固定顺序读取 `core/`、`platforms/`、`commands/` 和 `main.ps1`。
2. 生成带完整注释帮助的单文件脚本。
3. 把 `docs/help.md` 同步复制或渲染为独立帮助文档。
4. 在构建阶段校验所有必需片段都已被纳入，避免漏拼。

这样可以保证开发期与分发期的边界清晰：

- 开发时维护多文件源码，便于阅读与测试。
- 分发时只需要携带一个脚本和一份帮助文档。

## CLI Design

对外入口采用统一子命令风格：

```powershell
./Postgres-Toolkit.ps1 <command> [options]
```

第一版支持以下子命令：

- `backup`
- `restore`
- `import-csv`
- `install-tools`
- `help`

建议帮助示例：

```powershell
./Postgres-Toolkit.ps1 backup --database app --output ./app.dump --format custom
./Postgres-Toolkit.ps1 restore --input ./app.dump --target-database app_restore --clean
./Postgres-Toolkit.ps1 import-csv --input ./users.csv --table users --header
./Postgres-Toolkit.ps1 install-tools --apply
./Postgres-Toolkit.ps1 help restore
```

### Common Options

所有涉及数据库连接的命令统一支持以下参数：

- `--connection-string`
- `--host`
- `--port`
- `--user`
- `--password`
- `--database`
- `--env-file`
- `--verbose`
- `--dry-run`

### Connection Precedence

连接信息优先级定义为：

1. 显式参数
2. `--connection-string`
3. `--env-file` 中的 `PG*` 变量
4. 当前进程环境中的 `PG*` 变量

其中支持的标准变量至少包括：

- `PGHOST`
- `PGPORT`
- `PGUSER`
- `PGPASSWORD`
- `PGDATABASE`

这样既保留类 Unix 生态习惯，也兼容更接近 CLI 工具的显式传参方式。

## Command Behavior

### backup

`backup` 底层封装 `pg_dump`，目标是覆盖最常见的单库备份场景。

建议支持的重点参数：

- `--output`
- `--format custom|plain|directory|tar`
- `--schema`
- `--table`
- `--exclude-table`
- `--data-only`
- `--schema-only`
- `--jobs`
- `--compress`

设计规则如下：

- 默认格式为 `custom`。
- 只有 `directory` 格式允许并行备份；如果用户在其他格式下传入 `--jobs`，应给出清晰错误。
- `schema-only` 与 `data-only` 互斥。
- 所有输出路径在执行前都做基本合法性校验。

### restore

`restore` 根据输入自动选择 `psql` 或 `pg_restore`，避免用户手动记忆恢复工具。

建议支持的重点参数：

- `--input`
- `--target-database`
- `--create-database`
- `--clean`
- `--if-exists`
- `--no-owner`
- `--no-privileges`
- `--schema`
- `--table`
- `--data-only`
- `--schema-only`
- `--jobs`

格式识别规则：

- `.sql` -> `psql -f`
- `.dump` / `.backup` / `.tar` -> `pg_restore`
- 目录路径 -> `pg_restore -Fd`

不允许做模糊猜测；当输入既不是支持的扩展名，也不是目录时，应直接报错。

### import-csv

`import-csv` 默认使用 `psql` 的 `\copy` 语法，把本地 CSV 导入到已存在表。

建议支持的重点参数：

- `--input`
- `--table`
- `--schema`
- `--delimiter`
- `--header`
- `--encoding`
- `--null-string`
- `--truncate-first`
- `--columns`

设计规则如下：

- 第一版不创建表，目标表必须已存在。
- 默认通过 `\copy` 读取本地文件，避免服务器端 `COPY` 对文件路径的额外要求。
- `--truncate-first` 属于高风险操作，需要显式提示。
- 当传入 `--columns` 时，只导入指定列，并要求列顺序与 CSV 内容对应。

### install-tools

`install-tools` 负责检测 PostgreSQL CLI 是否存在，并给出跨平台安装建议。

建议支持的重点参数：

- `--apply`
- `--tool`
- `--package-manager auto|winget|choco|brew|apt|dnf|yum|apk`

设计规则如下：

- 默认只输出建议安装命令，不执行。
- 仅在传入 `--apply` 时执行安装命令。
- 若用户显式指定包管理器，则优先使用该策略。
- 若未指定，则按平台自动选择最合适的包管理器。
- 工具检测范围至少覆盖 `psql`、`pg_dump`、`pg_restore`、`pg_dumpall`。

### help

`help` 负责输出命令总览、子命令说明和示例，并与独立帮助文档保持一致。

建议支持：

- `help`
- `help backup`
- `help restore`
- `help import-csv`
- `help install-tools`

## Execution Flow

所有子命令建议统一走以下流程：

1. 解析 CLI 参数。
2. 合并显式参数、连接串、环境变量和 `.env` 文件。
3. 校验当前子命令所需工具是否存在。
4. 将用户参数翻译成 PostgreSQL 官方 CLI 参数数组。
5. 若为 `--dry-run`，输出最终命令、连接来源和关键推断结果。
6. 正式执行底层命令，并对输出与退出码做统一处理。

统一执行流的好处是：

- 各命令的日志和错误体验一致。
- 更容易做 fake executable 风格测试。
- 后续增加子命令时可以复用公共流程。

## Documentation Strategy

文档建议分三层：

1. 源码目录中的 `README.md`
   说明项目目标、目录结构、构建方法、命令总览和常见示例。
2. 源码目录中的 `.env.example`
   提供 `PG*` 环境变量示例，帮助用户快速理解连接配置方式。
3. 构建产物 `Postgres-Toolkit.Help.md`
   提供完整帮助文本，适合在不执行脚本时直接阅读。

同时，单文件脚本自身也应内嵌与帮助文档一致的 `help` 输出，避免“文档与实际入口割裂”的体验。

## Error Handling

统一错误处理至少覆盖以下类别：

- 参数错误
- 依赖缺失
- 输入文件不存在
- 输入格式不支持
- 数据库连接失败
- 认证失败
- PostgreSQL 底层命令执行失败

设计约束如下：

- 错误信息应同时包含失败原因和下一步建议。
- 日志、dry-run 和错误消息里不能输出明文密码。
- `restore --clean` 与 `import-csv --truncate-first` 这类高风险动作应有明确提示。
- 默认输出保持简洁，`--verbose` 才输出完整底层命令与解析细节。

## Security and Safety

第一版保持保守默认值，避免误操作：

- 不在日志中输出敏感连接信息。
- 不自动创建数据库或表，除非用户显式要求相关动作。
- 对覆盖型操作增加提示。
- 尽量用参数数组而不是字符串拼接调用外部进程，降低转义和注入风险。

## Testing Strategy

测试框架采用仓库现有的 Pester 体系，重点覆盖“参数解析正确”和“最终调用正确”。

建议测试分层如下：

### Unit Tests

- 连接优先级解析
- `.env` 与环境变量合并
- 输入格式识别
- 各子命令参数翻译结果
- 平台安装命令生成
- 帮助文本输出

### Fake Executable Integration Tests

像 `tests/Invoke-Benchmark.Tests.ps1` 一样，在临时目录放置假的：

- `psql`
- `pg_dump`
- `pg_restore`
- `pg_dumpall`

通过这些 fake executable 断言：

- 是否调用了正确工具
- 参数是否正确透传
- dry-run 是否不会真正执行
- 不同命令分支是否按预期选择

### Build Verification Tests

- 构建脚本是否生成单文件脚本与帮助文档
- 构建产物是否包含所有命令入口
- 构建产物的 `help` 输出是否与帮助文档一致

第一版不把真实 PostgreSQL 服务作为必需测试依赖；如后续需要，再独立补充 Docker 或容器化 smoke test。

## Verification Plan

实现完成后至少验证以下路径：

1. 构建脚本成功生成 `Postgres-Toolkit.ps1` 与 `Postgres-Toolkit.Help.md`。
2. `help` 与独立帮助文档都能看到四个核心子命令和示例。
3. `backup --dry-run` 能正确输出 `pg_dump` 调用方案。
4. `restore` 能根据 `.sql`、`.dump`、目录输入选择正确恢复工具。
5. `import-csv --dry-run` 能正确构造 `\copy` 方案，并保护高风险选项提示。
6. `install-tools` 能根据不同平台生成合理安装命令，并在 `--apply` 下调用正确包管理器。
7. fake executable 集成测试能够覆盖主要命令分支和失败路径。

## Trade-offs

本设计主动接受以下取舍：

- 第一版只支持导入到已存在表，换取更低复杂度和更可预测的行为。
- 安装能力默认只输出建议命令，而不是无提示自动安装，换取更稳妥的跨平台体验。
- 使用 PostgreSQL 官方 CLI 作为底层能力中心，意味着某些高级能力仍然需要用户显式传参或后续扩展。

这些取舍符合第一版以“可靠覆盖常用场景”为优先目标的范围控制。

## Deferred Work

如果后续需求继续增长，可在独立变更中考虑：

- 自动建表与有限的列类型推断
- 更多备份过滤参数
- 真正连接数据库做表存在性预检
- Docker 驱动的端到端 smoke test
- 生成跨平台 launcher 或安装器

这些内容不属于本次设计范围。
