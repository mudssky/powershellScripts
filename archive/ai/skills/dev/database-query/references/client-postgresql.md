# PostgreSQL 客户端参考

## 推荐工具

使用官方 `psql`。`database-query client` 会从配置读取连接参数，并把密码放入子进程环境变量 `PGPASSWORD`，不要把密码写进命令行。

## 配置映射

- `host` -> `psql -h`
- `port` -> `psql -p`
- `username` -> `psql -U`
- `database` / `defaultDatabase` -> `psql -d`
- `password` -> `PGPASSWORD`

## 常用命令

```bash
node scripts/database-query.js exec --sql "select id from users limit 10" --verbose
node scripts/database-query.js client --print-command -- --set ON_ERROR_STOP=1
node scripts/database-query.js client -- --set ON_ERROR_STOP=1
node scripts/database-query.js config discover-databases --instance local-postgres
node scripts/database-query.js config discover-databases --instance local-postgres --write
```

`config discover-databases` 默认只预览。传 `--write` 时只写回 `*.local.json`，并先在同目录创建 `.bak`；没有 `defaultDatabase` 时默认连接 `postgres`，也可以用 `--database <name>` 指定发现连接库。

需要执行 SQL 文件时，先单独检查文件：

```bash
node scripts/database-query.js check-sql --dialect postgres --level readonly --file ./query.sql
node scripts/database-query.js client -- --set ON_ERROR_STOP=1 -f ./query.sql
```

## 只读排障

在 `psql` 内优先使用这些只读命令：

```sql
\conninfo
\dt
\d users
select * from information_schema.tables limit 50;
select id, created_at from users limit 50;
explain select id from users where id = 1 limit 1;
```

## 风险边界

- `COPY ... TO`、`\copy`、`\o`、大范围导出需要用户确认。
- `\i` 执行外部文件前必须先确认文件内容，SQL 文件还要先运行 `check-sql`。
- `DROP`、`ALTER`、`CREATE`、`INSERT`、`UPDATE`、`DELETE`、`TRUNCATE`、锁表和长事务都属于高风险操作。
