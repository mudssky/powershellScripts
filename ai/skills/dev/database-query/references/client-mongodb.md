# MongoDB Shell 参考

## 推荐工具

使用 `mongosh`。`database-query client` 会从配置读取 `uri`，并在命令预览中脱敏用户名和密码。

## 配置映射

- `uri` -> `mongosh <uri>`
- `database` / `defaultDatabase` -> 写入 URI path
- `collections` / `defaultCollection` -> 供 `exec` 的 `find`、`count` 等动作自动解析

## 常用命令

```bash
node scripts/database-query.js exec --action list-collections --verbose
node scripts/database-query.js exec --action count --collection users --query "{}"
node scripts/database-query.js exec --action find --collection users --query "{\"status\":\"active\"}" --limit 20
node scripts/database-query.js client --print-command -- --quiet
node scripts/database-query.js client -- --quiet
```

## 只读排障

```javascript
db.getCollectionNames()
db.users.countDocuments({})
db.users.find({ status: 'active' }).limit(20).toArray()
db.users.getIndexes()
```

## 风险边界

- 禁止自动透传 `insertOne`、`insertMany`、`update*`、`delete*`、`drop`、`dropDatabase`。
- `aggregate` 中的 `$out`、`$merge` 属于写入风险。
- `--eval` 只适合短小只读脚本；复杂脚本需要先展示内容并让用户确认。
