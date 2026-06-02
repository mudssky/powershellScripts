# MySQL 客户端参考

## 推荐工具

使用 `mysql` CLI。`database-query client` 会从配置读取连接参数，并把密码放入子进程环境变量 `MYSQL_PWD`，命令预览只显示脱敏值。

## 配置映射

- `host` -> `mysql --host`
- `port` -> `mysql --port`
- `username` -> `mysql --user`
- `database` / `defaultDatabase` -> `mysql --database`
- `password` -> `MYSQL_PWD`

## 常用命令

```bash
node scripts/database-query.js exec --sql "select id from users limit 10" --verbose
node scripts/database-query.js client --print-command -- --batch --raw
node scripts/database-query.js client -- --batch --raw
```

需要执行 SQL 文件时，先单独检查文件：

```bash
node scripts/database-query.js check-sql --dialect mysql --level readonly --file ./query.sql
node scripts/database-query.js client -- --batch --raw < ./query.sql
```

## 只读排障

```sql
show databases;
show tables;
describe users;
select table_name from information_schema.tables limit 50;
select id, created_at from users limit 50;
explain select id from users where id = 1 limit 1;
```

## 风险边界

- `SELECT ... INTO OUTFILE`、`mysqldump`、大范围导出需要用户确认。
- 避免在命令行里使用 `--password=...`，会暴露在进程列表和日志里。
- `DROP`、`ALTER`、`CREATE`、`INSERT`、`UPDATE`、`DELETE`、`TRUNCATE`、`LOCK TABLES` 都属于高风险操作。
