# Postgres Toolkit Help

## Commands

- `backup`
- `restore`
- `import-csv`
- `pgbackrest`
- `install-tools`

## Connection Defaults

- If `--env-file` is provided, the toolkit reads only that file.
- If `--env-file` is omitted, the toolkit auto-discovers `.env` and `.env.local` from the current working directory first, then falls back to the script directory only when the current working directory has neither file.
- Connection precedence is: explicit options, `--connection-string`, explicit `--env-file`, current process `PG*` variables, then auto-discovered env files.

## Examples

```powershell
./Postgres-Toolkit.ps1 backup --database app --output ./app.dump --format custom
./Postgres-Toolkit.ps1 backup --dry-run --output ./app.dump
./Postgres-Toolkit.ps1 backup --database app --table public.orders --output ./orders.dump
./Postgres-Toolkit.ps1 pgbackrest --action backup --type incr --config ./pgbackrest.conf.local --dry-run
```

## Backup Scope

- `backup` 使用 `pg_dump`，适合单库、schema、表级逻辑快照；它不是通用增量备份工具。
- `pgbackrest` 使用 pgBackRest，适合整个 PostgreSQL cluster 的 full/diff/incr 物理备份和 PITR。
