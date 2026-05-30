# Milvus SDK 参考

## 推荐工具

Milvus 首版使用官方 Node.js SDK `@zilliz/milvus2-sdk-node` 执行少量只读动作。`database-query.js` 不把 SDK 打进单文件，`doctor` 会提示 SDK 是否可用。

## 配置映射

- `address` / `uri` -> `new MilvusClient({ address })`
- `token` -> `MilvusClient` 鉴权参数
- `database` / `defaultDatabase` -> 上下文分组；首版不强行映射为所有 Milvus 部署的 database 参数
- `collections` / `defaultCollection` -> `collection_name`

## 常用命令

```bash
node scripts/database-query.js doctor
node scripts/database-query.js exec --action list-collections --verbose
node scripts/database-query.js exec --action describe-collection --collection documents
node scripts/database-query.js exec --action query --collection documents --query "id > 0" --limit 20
node scripts/database-query.js exec --action search --collection documents --vector "[0.1,0.2,0.3]" --limit 5
```

## 只读 SDK 动作

- `showCollections()`：列出 collection。
- `describeCollection({ collection_name })`：查看 schema。
- `query({ collection_name, filter, limit })`：按标量过滤读取数据。
- `search({ collection_name, data, filter, limit })`：向量检索。

## 风险边界

- 禁止自动执行 `dropCollection`、`truncateCollection`、`delete`、`insert`、`upsert`、索引重建等写入或管理动作。
- `search` 的 vector 必须来自用户明确提供或当前任务可靠生成，不要凭猜测构造生产检索。
- 查询和检索必须设置 `limit`，并遵守配置中的 `maxLimit`。
