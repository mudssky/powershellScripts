# SQL Guard 参考

## 目标

`scripts/database-query.js check-sql` 是执行关系型 SQL 前的轻量静态安全检查。它只读取 SQL 文本，不连接数据库，也不执行 SQL。`exec` 执行 PostgreSQL/MySQL/SQLite SQL 时会自动调用同一套 guard。

## 权限层级

| 层级 | 用途 | 行为 |
|------|------|------|
| `readonly` | 默认查询 | 只允许只读查询，要求结果限制 |
| `maintenance` | 排障维护 | 允许 `EXPLAIN`、`SHOW`、`DESCRIBE`、`PRAGMA` 等检查语句，阻断写入和破坏性语句 |
| `admin` | 管理建议 | 放宽管理语句，但导出等极高风险动作仍阻断 |
| `yolo` | 用户接管静态风险 | 将静态阻断降级为警告；执行危险操作仍需用户明确确认 |

## 命令

```bash
node scripts/database-query.js check-sql --dialect postgres --level readonly --sql "select id from users limit 10"
node scripts/database-query.js check-sql --dialect mysql --level readonly --file ./query.sql
node scripts/database-query.js check-sql --dialect sqlite --level yolo --file ./migration.sql
```

## 规则

- 阻断多语句，避免把查询和危险操作混在一起。
- 阻断 `DROP`、`TRUNCATE`、`ALTER`、`CREATE`、`UPDATE`、`DELETE`、`INSERT`、`MERGE`、`REPLACE` 等高风险语句。
- 阻断或警告导出相关语句，例如 PostgreSQL `COPY ... TO`、MySQL `INTO OUTFILE`、SQLite `.dump`。
- 检查只读查询是否缺少 `LIMIT` / `FETCH FIRST` / `TOP`。
- 检查 `LIMIT` 是否超过当前 `--max-limit`。
- 标记锁、事务和危险函数，例如 `FOR UPDATE`、`LOCK TABLE`、`pg_read_file`、`xp_cmdshell`。

## 注意

- 静态检查通过不代表 SQL 一定安全。
- 只读账号、数据库权限、人工确认和小结果集策略仍是主要安全边界。
- `yolo` 只跳过脚本阻断，不代表 agent 可以自动执行危险 SQL。
