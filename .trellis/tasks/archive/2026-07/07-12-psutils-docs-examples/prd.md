# 修复 psutils 文档与示例可靠性

## Goal

让 README、docs、examples 和 demo 与真实模块入口、版本、API 和运行行为一致，并能通过自动检查防止再次漂移。

## Background

- README 的模块数量、按需加载、完整帮助、ffmpeg 模块和版本信息已与源码不符。
- 多个 demo 与树示例导入不存在的路径或空入口。

## Requirements

- 在核心契约任务确定入口和命令名后同步所有用户文档。
- 修复或归档无法代表当前行为的 examples/demo；保留项必须使用规范入口或明确的子模块入口。
- README 不再推荐已弃用的帮助搜索主路径，也不维护容易漂移的手工事实。
- 增加无网络、无系统修改的文档/示例可发现性或 smoke 检查。

## Acceptance Criteria

- [x] README 的版本、支持范围、入口、模块能力和测试命令与代码一致。
- [x] 所有保留 example/demo 的模块路径存在；可安全执行的示例通过 smoke 检查。
- [x] 文档不再把弃用 API 描述为推荐方案。
- [x] 文案之外的 PowerShell 改动通过包级与根级 QA。

## Out of Scope

- 改变公共函数行为。
- 为展示样式创建额外测试页面或演示框架。
- 重写已由测试覆盖且事实正确的所有文档。

## Dependencies

- 依赖 `07-12-psutils-core-contract` 确定规范入口、版本和命令名。
