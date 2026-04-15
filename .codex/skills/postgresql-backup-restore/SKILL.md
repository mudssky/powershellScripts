---
name: postgresql-backup-restore
description: Use when 需要在这个仓库或通用 shell 环境中执行 PostgreSQL 备份、恢复、命令行工具安装提示，或快速确认 pg_dump、pg_restore、psql、globals 备份的可靠用法。
argument-hint: "[场景，例如 备份单库 / 恢复 dump / 安装 pg_dump]"
disable-model-invocation: true
---

# PostgreSQL 备份与恢复

用于在这个仓库里快速找到 PostgreSQL 备份、恢复、工具安装和脚本化执行的可靠入口。

## Quick Start

先记住 4 条：

- 单库备份优先用 `pg_dump`
- 恢复 `.sql` 用 `psql`
- 恢复 `.dump`、`.backup`、`.tar` 和目录格式用 `pg_restore`
- 角色/表空间等 globals 用 `pg_dumpall --globals-only`

常用入口：

```bash
# Bash 辅助脚本
bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh help
bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh install-hint --platform linux --manager apt
PGPASSWORD=secret bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh backup --host 127.0.0.1 --user postgres --database app --output ./app.dump --dry-run
PGPASSWORD=secret bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh restore --host 127.0.0.1 --user postgres --database app_restore --input ./app.dump --clean --if-exists --dry-run

# PowerShell 工具
pwsh -NoProfile -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 backup --database app --output ./app.dump --format custom --dry-run
pwsh -NoProfile -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 restore --database app_restore --input ./app.dump --clean --dry-run
```

详细安装命令、globals 备份/恢复、CSV 导入入口见 [reference.md](reference.md)。

## When to Use

适用于这些场景：

- 需要快速判断 `.sql` 和 `.dump` 应该分别用哪个工具恢复
- 需要给 Linux、macOS、Windows 输出 PostgreSQL CLI 安装命令
- 需要在 Bash 环境里快速拼出 `pg_dump` / `pg_restore` / `psql` 命令
- 需要复用仓库里的 [Postgres-Toolkit.ps1](../../../scripts/pwsh/devops/Postgres-Toolkit.ps1) 或 skill 自带的 [pg-backup-restore.sh](pg-backup-restore.sh)

不适用于这些场景：

- 自动建表、类型推断、迁移 diff
- 长期双向同步或 CDC
- 复杂 DBA 级性能调优

## Quick Reference

| 场景 | 工具 | 推荐入口 |
|---|---|---|
| 备份单个数据库 | `pg_dump` | `Postgres-Toolkit.ps1 backup` / `pg-backup-restore.sh backup` |
| 恢复 SQL 文本 | `psql` | `Postgres-Toolkit.ps1 restore` / `pg-backup-restore.sh restore` |
| 恢复归档或目录 | `pg_restore` | `Postgres-Toolkit.ps1 restore` / `pg-backup-restore.sh restore` |
| 安装 CLI 工具 | 包管理器 | `pg-backup-restore.sh install-hint` |
| CSV 导入现有表 | `psql \copy` | `Postgres-Toolkit.ps1 import-csv` |

## Instructions

1. 先识别输入类型，再选工具。
   `.sql -> psql`，`.dump/.backup/.tar/目录 -> pg_restore`。

2. 优先使用不暴露密码的方式。
   首选 `PGPASSWORD`、`.env` 或进程环境变量；避免把密码直接写进 shell 历史。

3. 需要 Bash 环境辅助时，直接调用 [pg-backup-restore.sh](pg-backup-restore.sh)。
   这个脚本提供 `install-hint`、`backup`、`restore` 三个命令，并支持 `--dry-run`。

4. 需要更强的跨平台体验时，优先调用 [Postgres-Toolkit.ps1](../../../scripts/pwsh/devops/Postgres-Toolkit.ps1)。
   它额外支持 `import-csv` 和 `install-tools --apply`。

## Common Mistakes

- 把 `.sql` 交给 `pg_restore`
- 在非 `directory` 格式下使用并行 `-j`
- 备份或恢复时把密码直接写进命令行
- 只恢复业务库，却漏掉角色/表空间这类 globals
