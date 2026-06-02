# pgBackRest 远程备份模板

这个目录用于维护 `macmini` 上 PostgreSQL / LobeChat 数据库的备份方案。设计目标是：任意加入同一 Tailscale 网络、能访问 `macmini` 或它的 Tailscale IP 的机器，都可以触发备份。

## 先厘清边界

- **pgBackRest 物理备份**：备份 PostgreSQL 实例的数据目录和 WAL，适合整实例灾备、差异/增量备份、PITR。它不能只备份 `lobechat` 里的某张表。
- **pg_dump 逻辑备份**：通过 PostgreSQL TCP 连接备份单个数据库、schema 或表，适合 “备份整个 `lobechat` 数据库” 和 “备份 `public.xxx` 某张表”。它每次产生的是逻辑快照，不提供通用增量备份。
- **Tailscale 的角色**：只解决网络可达性和访问控制。pgBackRest 远程物理备份仍需要 SSH 或 pgBackRest TLS server 作为远程执行协议。

推荐组合：

- 整实例灾备：`pgBackRest + Tailscale + SSH`
- 单库/单表导出：`Postgres-Toolkit.ps1 backup + Tailscale PostgreSQL TCP`
- 单库/单表“增量”：不使用 `pg_dump` 伪装成备份；需要增量时做 pgBackRest 整实例增量，或为特定业务表单独设计按 `updated_at` / 事件日志导出的同步任务。

## 文件说明

- `pgbackrest.conf.local.example`：pgBackRest 配置模板，复制为 `pgbackrest.conf.local` 后编辑。
- `pgbackrest.env.local.example`：`Postgres-Toolkit.ps1 pgbackrest` 的默认值模板，复制为 `pgbackrest.env.local` 后可通过 `--env-file` 使用。
- `.gitignore`：忽略真实 `.local` 配置、日志和备份产物。

真实密码不要提交到 Git。建议用 `PGPASSFILE` 或临时 `export PGPASSWORD=...`。

## 首次准备

在执行备份的机器上：

```bash
cd config/database/backup/pgBackRest
cp pgbackrest.conf.local.example pgbackrest.conf.local
cp pgbackrest.env.local.example pgbackrest.env.local
chmod 600 pgbackrest.env.local
```

编辑 `pgbackrest.conf.local`：

- `repo1-path`：建议改成固定备份盘、NAS 挂载点或长期在线备份机路径。
- `pg1-host`：写 `macmini`、MagicDNS 名称或 Tailscale IP。
- `pg1-host-user`：默认示例是 `postgres`，需要能从执行机 SSH 到 macmini。
- `pg1-path`：PostgreSQL data directory。Docker/ParadeDB 场景通常是容器内 `/var/lib/postgresql/data`，必须保证远程 pgBackRest 能读到这个路径。

编辑 `pgbackrest.env.local`：

- `PGBR_DB_HOST`：`macmini` 或 Tailscale IP。
- `PGBR_DB_NAME`：默认 `lobechat`。
- `PGBR_DB_USER`：默认 `postgres`。
- `PGPASSFILE` 或 `PGPASSWORD`：用于 `pg_dump` 逻辑备份。

## 远程物理备份要求

要从任意机器执行 pgBackRest 物理备份，至少需要：

1. 执行机安装 `pgbackrest`、`ssh`。
2. macmini 安装 `pgbackrest`，并允许执行机通过 Tailscale SSH 登录。
3. macmini 上 pgBackRest 能读取 PostgreSQL data directory。
4. 若需要 PITR，macmini 的 PostgreSQL 必须配置 `archive_command`，把 WAL 持续归档到同一个 pgBackRest 仓库。

重要提醒：如果你在不同机器上各自使用本地 `repo1-path`，备份会分散。长期方案建议固定一台备份机或一个共享仓库路径。

## 常用命令：pgBackRest 物理备份

先做本地检查：

```powershell
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest `
  --env-file ./pgbackrest.env.local `
  --config ./pgbackrest.conf.local `
  --action check `
  --dry-run
```

预览 pgBackRest 命令：

```powershell
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest `
  --env-file ./pgbackrest.env.local `
  --config ./pgbackrest.conf.local `
  --action backup `
  --type full `
  --dry-run
```

初始化 stanza：

```powershell
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest `
  --env-file ./pgbackrest.env.local `
  --config ./pgbackrest.conf.local `
  --action stanza-create
```

执行物理备份：

```powershell
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest `
  --env-file ./pgbackrest.env.local `
  --config ./pgbackrest.conf.local `
  --action backup `
  --type full

pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest --action backup --type diff
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest --action backup --type incr
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest --action info
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 pgbackrest --action expire
```

## 逻辑备份：整个 lobechat 数据库

只要执行机能通过 Tailscale 访问 `macmini:5432`，就可以使用 `pg_dump`：

```powershell
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 backup `
  --connection-string 'postgresql://postgres:REPLACE_ME@macmini:5432/lobechat' `
  --output ./table-dumps/lobechat.dump `
  --format custom
```

默认输出到 `table-dumps/`，格式为 custom dump，恢复时使用 `pg_restore`。

自定义输出：

```powershell
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 backup `
  --host macmini `
  --port 5432 `
  --user postgres `
  --database lobechat `
  --output ./table-dumps/lobechat.dump `
  --format custom
```

## 逻辑备份：某个数据库某张表

表级备份最佳实践是 `pg_dump -t`：

```powershell
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 backup `
  --connection-string 'postgresql://postgres:REPLACE_ME@macmini:5432/lobechat' `
  --table public.messages `
  --output ./table-dumps/lobechat_public_messages.dump `
  --format custom
```

也可以拆开 schema 和表名：

```powershell
pwsh -File ../../../../scripts/pwsh/devops/Postgres-Toolkit.ps1 backup `
  --host macmini `
  --database lobechat `
  --schema public `
  --table messages `
  --output ./table-dumps/lobechat_public_messages.dump
```

恢复单表时先查看 dump 内容，再只恢复目标表：

```bash
pg_restore -l ./table-dumps/lobechat_public.messages_YYYYMMDD-HHMMSS.dump
pg_restore -h macmini -p 5432 -U postgres -d lobechat -t public.messages \
  ./table-dumps/lobechat_public.messages_YYYYMMDD-HHMMSS.dump
```

## 为什么不用 pg_dump 做增量

`pg_dump` 是逻辑导出工具：它知道如何把当前可见的数据和结构导出成 dump，但不会维护“上次备份以来哪些数据块变化了”的备份链。用 `WHERE updated_at > ...`、触发器、审计表或 CDC 导出变化可以做同步任务，但那已经是业务数据管道，不是通用备份：

- 需要每张表都有可靠的更新时间、删除标记或事件日志。
- 需要单独处理 schema 变更、外键关系、删除数据和幂等恢复。
- 恢复时很难像备份工具一样保证一致时间点。

所以当前模板的策略是：

- 恢复整库/误删兜底：用 pgBackRest 的 full/diff/incr 和 WAL。
- 临时抽取某张表：用 `Postgres-Toolkit.ps1 backup --table ...` 做一次逻辑快照。

## PostgreSQL 端 WAL 归档提示

pgBackRest 要做可靠 PITR，需要 PostgreSQL 持续归档 WAL。典型配置形态如下，实际路径要按 macmini 上的配置文件位置调整：

```conf
archive_mode = on
archive_command = 'pgbackrest --stanza=lobechat archive-push %p'
```

如果 PostgreSQL 在 Docker 容器里运行，通常需要把 pgBackRest 安装进容器、使用 sidecar，或把数据卷与 pgBackRest 配置正确挂载到可执行环境中。只开放 `5432` 端口不足以完成 pgBackRest 物理备份，但足够执行 `pg_dump` 逻辑备份。
