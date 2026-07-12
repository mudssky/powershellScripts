# psutils API 与模块边界设计

## API Classification

实施时生成 `api-inventory.md`，为每个当前 manifest 导出标记以下类别之一：

- Stable User：README、Profile 或常用交互命令依赖的稳定 API。
- Shared Repository：仓库脚本复用但不一定面向交互用户的共享 API。
- Compatibility：为旧名称或旧参数保留的迁移层。
- Diagnostic：benchmark、诊断或维护命令，不默认承诺长期稳定。
- Private：实现 helper，不应由模块导出。

仓库零调用只能作为 Private/Diagnostic 候选证据，不能单独决定删除。

## Export Boundary

- 所有子模块使用显式 `Export-ModuleMember`。
- manifest 只列出有明确分类的公共命令。
- `wrapper.psm1` 的默认描述前缀改为 script scope 或参数默认常量，不在导入时写入全局变量。
- 同名命令由一个公共 wrapper 或权威实现拥有参数契约。

## Module Responsibility

- `functions.psm1` 按交互历史、包文件编辑、数学/格式 helper 等真实职责评估拆分。
- `help.psm1` 区分用户帮助命令、内部 parser 和 benchmark；已弃用搜索链保留兼容入口但不继续扩张。
- `test.psm1` 区分运行时应用探测与真正测试 helper，避免模块名误导。
- 仅当拆分降低依赖、冲突或加载成本时实施；否则保留文件并只收紧导出。

## Help Contract

- API inventory 完成后，只为 Stable User、Shared Repository 和 Compatibility 命令补齐面向使用者的帮助。
- 所有保留公共函数说明核心功能、全部参数和返回值；无结构化返回的交互命令明确 `.OUTPUTS None`。
- Private helper 仅保留解释复杂设计意图所需的中文注释。

## Performance

- 记录聚合 manifest、Profile 同步模块和直接子模块导入的多样本中位数。
- 不改变 Profile 的同步轻量加载与 OnIdle 全量加载架构。
- CI 不设置绝对毫秒阈值；本机出现超过 10% 的稳定回归时需要解释或回退。

## Migration

- Stable User 命令重命名时保留 wrapper 或参数 alias。
- Shared Repository 命令可在同一任务中迁移全部仓库消费者。
- Private 泄漏可直接停止导出，但先用 AST 和文本检索复核消费者。

## Rollback

- 兼容问题优先恢复导出/wrapper，不恢复 wildcard 或全局状态。
- 模块拆分导致作用域问题时回退文件移动，保留 API inventory 与显式导出改进。
