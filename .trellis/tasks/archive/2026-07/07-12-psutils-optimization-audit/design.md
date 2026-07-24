# psutils 优化审计设计

## Architecture

本任务是规划型父任务，不直接修改生产代码。它负责维护审计证据、跨任务决策、子任务依赖和最终集成验收。

执行树如下：

1. `07-12-psutils-core-contract` 建立 PowerShell 版本、入口和 API 契约基线。
2. `07-12-psutils-docs-examples` 基于已确定的入口与命令名修正文档和示例。
3. `07-12-psutils-api-boundaries` 基于契约测试收敛导出和模块职责。
4. `07-12-psutils-runtime-hardening` 在入口与 API 稳定后处理安全和健壮性候选。

后两个任务都依赖核心契约；运行时加固建议在 API 边界之后实施，以减少对同一模块的交叉修改。

## Decisions

- 主包支持 PowerShell 7.4+ / Core，不维护 5.1 双包。
- `psutils.psd1` 是规范入口；`index.psm1` 暂作弃用 shim。
- 文档化、Profile 和常用交互命令保持兼容；内部 helper 与意外导出允许直接收口。
- 不引入新的自定义懒加载框架，保留 Profile 已有同步轻量模块与 OnIdle 全量加载设计。
- 不以 PSScriptAnalyzer 告警数量或文件行数作为重构目标。

## Cross-Task Contracts

- 核心契约任务产出的 manifest/API 测试是后续任务的回归防线。
- 文档任务不得自行决定新的入口或重命名命令。
- API 边界任务不得改变 shared config resolver 与 WSL Docker wrapper 的既有行为规范。
- 运行时加固任务必须先复现或建立风险模型，再修改行为。

## Validation

- 每个子任务执行自己的窄测试、`pnpm qa` 和 `pnpm test:pwsh:all`。
- 父任务最终核对所有子任务验收、依赖顺序、README/API 一致性及 Profile 性能基线。
- 性能只做同机多样本相对比较，不进入跨机器绝对阈值。

## Rollback

- 每个子任务独立提交和归档，可按任务边界回退。
- 入口迁移失败时保留 `index.psm1` shim，不回退错误的 5.1 兼容声明。
- API 收敛或加固出现兼容问题时优先恢复 wrapper/导出，不撤销已经建立的契约测试。
