# psutils 文档与示例设计

## Documentation Source

- 版本、PowerShell 要求、入口和公共命令以 manifest 与实际导入结果为事实来源。
- README 避免维护容易漂移的精确模块数量；若确有必要，测试必须从 manifest 推导。
- 已弃用 API 只进入迁移说明，不再作为推荐路径。

## Example Policy

- example 用于说明稳定用户流程，必须引用规范 manifest 或明确的独立子模块。
- demo 只保留仍代表当前行为且路径正确的脚本；重复、版本过时或无法安全验证的 demo 可归档。
- smoke 检查默认只验证解析、导入路径和 `-WhatIf`/只读模式，不执行网络下载、系统代理、字体安装或文件破坏操作。

## Compatibility

- 文档更新依赖核心契约任务的最终入口、命令名和参数 alias；API inventory 后续私有化的内部 helper 不进入用户文档。
- 不在本任务更改函数行为或决定 API 删除。

## Rollback

- smoke 检查误触副作用时立即缩小为 AST/路径/帮助元数据检查。
- 归档 demo 前保留索引记录，必要时可恢复。
