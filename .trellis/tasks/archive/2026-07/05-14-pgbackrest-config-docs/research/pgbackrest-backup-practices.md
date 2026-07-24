# pgBackRest 配置与备份范围研究

## 结论摘要

- pgBackRest 的核心模型是 PostgreSQL 集群/实例级物理备份：通过 stanza 绑定一个 PostgreSQL data directory 与备份仓库，适合整库灾备、WAL 归档和 PITR。
- `pg1-host`、`pg1-path`、`repo1-path`、`repo1-retention-full` 等是配置示例的关键字段；远程备份时需要在数据库主机与备份主机上都能执行 `pgbackrest`。
- pgBackRest 不适合作为“只备份某个数据库某张表”的主工具；表级备份/恢复应使用 `pg_dump -t` / `pg_restore -t`，仓库已有 `docs/cheatsheet/database/postgresql/backup-restore.md` 和 `Postgres-Toolkit.ps1` 覆盖这个方向。
- 用户提供的连接串 `postgresql://postgres:12345678@macmini:5432/lobechat` 可用于逻辑表级脚本，但 pgBackRest 仍需要数据库服务器上的 `pg1-path`、WAL archive 配置和 pgBackRest stanza 初始化。
- 用户希望在任意能通过 Tailscale 访问 macmini 的机器执行备份。表级逻辑备份只需要 PostgreSQL TCP 可达；pgBackRest 整实例物理备份还需要通过 `pg1-host` 连接 macmini，并配置 `pg1-host-type=ssh` 或 `pg1-host-type=tls` 让执行机调用数据库主机上的 pgBackRest。
- `pg_dump` 不提供真正的增量备份语义，它每次输出的是当前逻辑快照；真正的增量链路应使用 pgBackRest 或 PostgreSQL 18+ 的 `pg_basebackup --incremental`。后者仍然是整个 cluster 级别，不能只备份单表。

## 官方文档依据

- Context7 `/websites/pgbackrest_configuration`：`pg1-host` 用于远程 PostgreSQL 主机；`pg1-database` 只指定 pgBackRest 连接 PostgreSQL 时使用的数据库，默认通常是 `postgres`，不是“只备份该数据库”的范围过滤。
- Context7 `/websites/pgbackrest_configuration`：`pg1-host-type` 支持 `ssh` 与 `tls` 两种协议类型，默认是 `ssh`；这意味着通过 Tailscale 网络远程运行 pgBackRest 是可行的，但数据库主机仍需安装并允许远程调用 pgBackRest。
- Context7 `/websites/pgbackrest_configuration`：`repo1-path` 指定备份仓库路径；`repo1-retention-full`、`repo1-retention-full-type`、`repo1-retention-diff`、`repo1-retention-history` 控制保留策略。
- PostgreSQL 官方 `pg_dump` 文档：表级备份使用 `-t/--table=PATTERN`，更适合单库、单 schema、单表这类逻辑范围备份。
- PostgreSQL 官方 `pg_basebackup` 文档：增量 base backup 属于整个 database cluster 级别，不能备份单个数据库或对象；选择性备份仍应使用 `pg_dump`。

## 映射到本仓库

- 目标目录已经存在：`config/database/backup/pgBackRest/`。
- 仓库已有 PostgreSQL 逻辑备份资料：
  - `docs/cheatsheet/database/postgresql/backup-restore.md`
  - `scripts/pwsh/devops/Postgres-Toolkit.ps1`
  - `scripts/pwsh/devops/postgresql/**`
- 因仓库已经有 `scripts/pwsh/devops/postgresql` 维护脚本，新增能力应优先扩展该 toolkit，而不是在 `config/database/backup/pgBackRest/` 下再创建一套 Bash 入口。
- LobeChat 相关文档确认本地常用数据库为 `lobechat`，用户这次明确要求连接 `macmini:5432/lobechat`。
- `.gitignore` 已忽略 `.env`、`.env.local`、`*.env.local`、`*.local.json`，但没有覆盖 `*.local.conf`；如果产出 `.local.conf` 且包含密码，应同时更新忽略规则或让 `.local.conf` 不含敏感值。

## 推荐方向

1. 在 `config/database/backup/pgBackRest/` 下提供可提交的示例配置与中文说明。
2. 用 `.local` 后缀存放本机真实配置入口，但不要提交真实密码；如果必须生成含密码文件，应确保 git 忽略。
3. 维护脚本入口统一放在 `scripts/pwsh/devops/postgresql` / `Postgres-Toolkit.ps1`：
   - `backup` 继续封装 `pg_dump`，负责单库、schema、表级逻辑快照。
   - 新增 `pgbackrest` 命令封装整实例物理备份维护：基于远程 `pg1-host=macmini`，支持 `check`、`stanza-create`、`backup full/diff/incr`、`info`、`expire`。
4. 默认推荐 Tailscale + SSH 模式：网络层由 Tailscale 提供可达性和访问控制，pgBackRest 远程协议用 SSH，避免额外维护 pgBackRest TLS server 证书。
5. 文档必须清楚说明：pgBackRest 负责整实例/PITR/增量，pg_dump 负责逻辑快照，单表没有通用“pg_dump 增量备份”。
