# PostgreSQL 备份与恢复参考

## 1. 安装命令行工具

### Windows

```powershell
winget install --id PostgreSQL.PostgreSQL --source winget
choco install postgresql --yes
```

### macOS

```bash
brew install libpq
brew link --force libpq
```

### Ubuntu / Debian

```bash
sudo apt-get update
sudo apt-get install -y postgresql-client
```

### Fedora / RHEL / Rocky

```bash
sudo dnf install -y postgresql
sudo yum install -y postgresql
```

### Alpine

```bash
sudo apk add postgresql-client
```

## 2. Bash 辅助脚本

脚本位置：

```bash
.codex/skills/postgresql-backup-restore/pg-backup-restore.sh
```

常用命令：

```bash
# 查看帮助
bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh help

# 输出安装提示
bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh install-hint --platform linux --manager apt

# 备份单库（dry-run）
PGPASSWORD=secret bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh backup \
  --host 127.0.0.1 \
  --user postgres \
  --database app \
  --output ./app.dump \
  --format custom \
  --dry-run

# 恢复 dump（dry-run）
PGPASSWORD=secret bash ./.codex/skills/postgresql-backup-restore/pg-backup-restore.sh restore \
  --host 127.0.0.1 \
  --user postgres \
  --database app_restore \
  --input ./app.dump \
  --clean \
  --if-exists \
  --dry-run
```

## 3. PowerShell 工具

仓库里已经有更强的 PowerShell 版本：

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 help
pwsh -NoProfile -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 backup --database app --output ./app.dump --format custom --dry-run
pwsh -NoProfile -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 restore --database app_restore --input ./app.dump --clean --dry-run
pwsh -NoProfile -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 import-csv --input ./users.csv --table users --header --dry-run
pwsh -NoProfile -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 install-tools
```

## 4. 常见直接命令

### 备份单库为 custom 格式

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d app -Fc -f ./app.dump
```

### 恢复 `.dump`

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d app_restore --clean --if-exists ./app.dump
```

### 备份为 SQL

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d app -Fp -f ./app.sql
```

### 恢复 `.sql`

```bash
psql -h 127.0.0.1 -p 5432 -U postgres -d app_restore -v ON_ERROR_STOP=1 -f ./app.sql
```

### 只备份 roles / tablespaces

```bash
pg_dumpall -h 127.0.0.1 -p 5432 -U postgres --globals-only -f ./globals.sql
```

### 恢复 globals

```bash
psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -f ./globals.sql
```

## 5. 选择规则

- 日常备份优先 `custom` 格式
- 大库并行备份优先 `directory` 格式
- 需要肉眼查看 SQL 时再用 `plain`
- `restore` 前先确认目标库、权限模型、是否需要 `--no-owner` / `--no-privileges`
