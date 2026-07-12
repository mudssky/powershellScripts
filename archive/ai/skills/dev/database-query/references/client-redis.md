# Redis CLI 参考

## 推荐工具

使用 `redis-cli`。`database-query client` 会从配置读取 `url`，并在命令预览中脱敏凭据。

## 配置映射

- `url` -> `redis-cli -u`
- `databases[].name` -> Redis 逻辑 DB 编号，仅用于上下文说明；首版不自动追加 `SELECT`。

## 常用命令

```bash
node scripts/database-query.js exec --action ping
node scripts/database-query.js exec --action scan --key "user:*" --limit 50
node scripts/database-query.js exec --action ttl --key "user:1"
node scripts/database-query.js exec --action get --key "user:1"
node scripts/database-query.js client --print-command -- --scan --pattern "user:*"
node scripts/database-query.js client -- --scan --pattern "user:*"
```

## 只读排障

```bash
PING
INFO
SCAN 0 MATCH user:*
TYPE user:1
TTL user:1
GET user:1
HGET user:1 name
LRANGE queue:jobs 0 49
```

## 风险边界

- 禁止自动执行 `DEL`、`UNLINK`、`FLUSHDB`、`FLUSHALL`、`EVAL`、`EVALSHA`、`CONFIG SET`、`SHUTDOWN`。
- `KEYS *` 可能阻塞生产实例，默认不要使用；优先 `SCAN`。
- 大 key 读取前先 `TYPE`、`TTL`，列表和集合类数据必须限制范围。
