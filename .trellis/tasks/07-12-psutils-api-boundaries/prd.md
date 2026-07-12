# 收敛 psutils 公共 API 与模块边界

## Goal

区分稳定用户 API、仓库共享 API、兼容 API、诊断命令和内部 helper，减少意外导出、名称冲突、全局状态和职责混杂，同时保持可控迁移。

## Background

- manifest 当前有 129 个唯一导出名，其中 69 个在仓库 PowerShell AST 中没有调用消费者。
- `wrapper.psm1` 与 `string.psm1` 使用 wildcard 导出，wrapper 导入还写入全局变量。
- `functions.psm1`、`help.psm1`、`test.psm1` 存在职责混杂或诊断能力进入公共面的迹象。

## Requirements

- 为当前导出命令建立 API 分层清单，不能仅以仓库零调用判定删除。
- README、Profile 和常用交互命令保持兼容；未文档化内部 helper、wildcard 意外导出及确认无消费者的内部命令允许直接私有化。
- 用显式导出替代 wildcard，并把模块配置限制在模块作用域。
- 处理重复命名、内部 helper 外泄、已弃用帮助链和诊断 benchmark 的归属。
- 只有在能够减少冲突、加载成本或维护风险时才拆分大型模块。
- 对需要迁移的公共命令提供兼容 wrapper、弃用警告或明确的一次性迁移方案。
- 为最终保留的公共函数补齐核心功能、全部参数和返回值说明；内部 helper 不增加面向用户的冗长帮助。
- 保留 Profile 已有同步轻量模块与 OnIdle 全量加载设计，并用测量验证性能影响。

## Acceptance Criteria

- [ ] 每个 manifest 导出都有稳定、兼容、诊断或待弃用分类及理由。
- [ ] 不再使用 wildcard 导出，不因导入模块新增无必要的全局变量。
- [ ] 同名公共命令只有一个权威参数契约。
- [ ] 被私有化或迁移的命令有仓库消费者迁移与兼容性验证。
- [ ] 最终保留的公共函数具有符合项目规范的参数和返回值说明。
- [ ] 聚合导入和 Profile 启动性能不出现未经解释的回归。
- [ ] `pnpm qa` 与 `pnpm test:pwsh:all` 通过。

## Out of Scope

- 为追求文件大小均匀而机械拆分模块。
- 未经兼容策略批准批量删除交互式用户命令。
- 重新设计共享配置解析器和 WSL Docker wrapper 的既有行为契约。

## Dependencies

- 依赖 `07-12-psutils-core-contract` 建立可信 API 基线。
- 公共 API 兼容策略已由父任务确定；若发现仓库外使用证据，再回到规划阶段调整具体命令的迁移方式。
