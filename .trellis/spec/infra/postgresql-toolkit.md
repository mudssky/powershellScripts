# PostgreSQL Toolkit Spec

> 本规范记录 `scripts/pwsh/devops/postgresql` 与 `config/database/backup/pgBackRest` 的备份命令边界、env 解析和测试约定。

## Scenario: Postgres Toolkit + pgBackRest Maintenance

### 1. Scope / Trigger

- Trigger: 修改 `scripts/pwsh/devops/postgresql/**`、`scripts/pwsh/devops/Postgres-Toolkit.ps1`、PostgreSQL 备份文档或 `config/database/backup/pgBackRest/**`。
- Scope: `Postgres-Toolkit.ps1` 是统一维护入口；配置目录只放可复制模板和 README，不再新增平行 Bash 维护脚本。
- Design intent: 逻辑备份和物理备份能力共用一个 CLI 分发、dry-run、构建和 Pester 测试体系，避免两套脚本漂移。

### 2. Signatures

- 逻辑快照：
  - `pwsh -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 backup --database app --output ./app.dump --format custom`
  - `pwsh -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 backup --database app --table public.orders --output ./orders.dump`
- pgBackRest 物理备份：
  - `pwsh -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest --action check --config ./pgbackrest.conf.local`
  - `pwsh -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest --action stanza-create --config ./pgbackrest.conf.local`
  - `pwsh -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest --action backup --type full|diff|incr --config ./pgbackrest.conf.local`
  - `pwsh -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest --action info|expire --config ./pgbackrest.conf.local`
- Build:
  - `pwsh -NoProfile -File ./scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1`

### 3. Contracts

- `backup` wraps `pg_dump` and creates logical snapshots. It is not a generic incremental backup mechanism.
- `pgbackrest` wraps `pgbackrest` and is the supported path for full/diff/incr physical backup chains.
- `backup`, `restore`, and `import-csv` may call `Resolve-PgContext` and use PostgreSQL connection defaults.
- `pgbackrest` must not call `Resolve-PgContext` before dispatch. It reads only explicit `--env-file` for `PGBR_*` values, so application `.env` files in the current directory cannot break physical-backup dry-runs.
- Supported `pgbackrest --action` values are `check`, `stanza-create`, `backup`, `info`, and `expire`.
- Supported `pgbackrest --type` values for `--action backup` are `full`, `diff`, and `incr`.

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| `pgbackrest --action restore` | Throw a validation error listing supported actions |
| `pgbackrest --action backup --type bad` | Throw a validation error listing `full`, `diff`, `incr` |
| Current directory has non-PostgreSQL `.env` | `pgbackrest --dry-run` must still succeed when options are explicit |
| `pgbackrest --env-file missing.local` | Throw `配置文件不存在` |
| `backup --jobs 4 --format custom` | Throw because pg_dump parallel backup requires `directory` format |

### 5. Good/Base/Bad Cases

- Good: Use `pgbackrest --action backup --type incr` for incremental disaster-recovery backups.
- Good: Use `backup --table public.orders` for a one-off logical table snapshot.
- Base: `pgbackrest --dry-run` returns a preview command without requiring `pgbackrest` installed.
- Bad: Add another maintenance script under `config/database/backup/pgBackRest` that duplicates toolkit behavior.
- Bad: Treat `pg_dump` as an incremental backup tool. Business-key exports based on `updated_at` are data pipelines, not generic backups.

### 6. Tests Required

- `New-PgBackRestCommandSpec` builds command arguments for full/diff/incr backups.
- Env-file defaults load `PGBR_CONFIG`, `PGBR_STANZA`, `PGBR_PG1_HOST`, `PGBR_PG1_HOST_TYPE`, and `PGBR_BACKUP_TYPE`.
- Invalid `pgbackrest --action` throws.
- Regression: `Invoke-PostgresToolkitCommand pgbackrest --dry-run` does not read current-directory `.env`.
- Build test confirms generated `Postgres-Toolkit.ps1` includes the new command.

### 7. Wrong vs Correct

#### Wrong

```powershell
$context = Resolve-PgContext -CliOptions $options
switch ($CommandName) {
    'pgbackrest' {
        $spec = New-PgBackRestCommandSpec -CliOptions $options
    }
}
```

问题：`pgbackrest` 不需要 PostgreSQL connection context，提前解析会读取当前目录 `.env`，导致应用配置文件污染物理备份命令。

#### Correct

```powershell
switch ($CommandName) {
    'backup' {
        $context = Resolve-PgContext -CliOptions $options
        $spec = New-PgBackupCommandSpec -CliOptions $options -Context $context
    }
    'pgbackrest' {
        $spec = New-PgBackRestCommandSpec -CliOptions $options
    }
}
```

理由：每个子命令只读取自己需要的配置来源，降低跨命令副作用。
