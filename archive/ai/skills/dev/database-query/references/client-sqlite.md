# SQLite 客户端参考

## 推荐工具

使用 `sqlite3` CLI。SQLite 通常没有网络凭据，`database-query client` 主要负责从配置读取 `path` 并启动客户端。

## 配置映射

- `path` -> `sqlite3 <path>`
- `database` 通常表示 `main` 或 attached database 的逻辑名，不作为连接参数。

## 常用命令

```bash
node scripts/database-query.js exec --sql "select id from users limit 10" --verbose
node scripts/database-query.js client --print-command -- --readonly
node scripts/database-query.js client -- --readonly
```

需要执行 SQL 文件时，先单独检查文件：

```bash
node scripts/database-query.js check-sql --dialect sqlite --level readonly --file ./query.sql
node scripts/database-query.js client -- --readonly < ./query.sql
```

## 只读排障

```sql
.tables
.schema users
pragma table_info(users);
select id, created_at from users limit 50;
explain query plan select id from users where id = 1 limit 1;
```

## 风险边界

- `.dump`、`.backup`、`.output` 可能导出大量数据，需要用户确认。
- `VACUUM`、`REINDEX`、`DROP`、`ALTER`、`INSERT`、`UPDATE`、`DELETE` 属于高风险操作。
- 只读场景优先透传 `--readonly`，避免意外写入数据库文件。
