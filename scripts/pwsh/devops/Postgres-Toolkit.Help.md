# Postgres Toolkit Help

## Commands

- `backup`
- `restore`
- `import-csv`
- `install-tools`

## Connection Defaults

- If `--env-file` is provided, the toolkit reads only that file.
- If `--env-file` is omitted, the toolkit auto-discovers `.env` and `.env.local` from the current working directory first, then falls back to the script directory only when the current working directory has neither file.
- Connection precedence is: explicit options, `--connection-string`, explicit `--env-file`, current process `PG*` variables, then auto-discovered env files.

## Examples

```powershell
./Postgres-Toolkit.ps1 backup --database app --output ./app.dump --format custom
./Postgres-Toolkit.ps1 backup --dry-run --output ./app.dump
```
