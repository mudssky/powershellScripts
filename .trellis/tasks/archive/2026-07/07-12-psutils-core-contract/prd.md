# 修复 psutils 兼容性与入口契约

## Goal

建立可信的 `psutils` 运行时基线：准确声明 PowerShell 版本、统一模块入口、修复 manifest/API 漂移，并让测试覆盖真实聚合导入方式。

## Background

- 主包兼容目标已确定为 PowerShell 7.4+ / Core。
- `index.psm1` 已失效但仍有消费者，聚合 manifest 还存在不存在的导出与同名函数覆盖。
- 本任务是其他 `psutils` 优化子任务的前置依赖。

## Requirements

- 将 manifest 的 `PowerShellVersion` 与 `CompatiblePSEditions` 同步为真实支持范围。
- 将 `psutils.psd1` 作为规范入口；旧 `index.psm1` 保留为带弃用提示的兼容 shim，仓库消费者不得继续依赖它。
- 迁移 `ai/downloadModels.ps1`、树示例及仓库内其他 `index.psm1` 消费者。
- 对齐 manifest、子模块导出和 Trellis 配置规范，包括 `Test-ModuleFunction`、配置 source reader 及重复 `New-Shortcut`。
- 增加聚合模块契约测试，校验导出存在、名称唯一、关键参数契约和独立子模块依赖。
- 不在本任务大规模收缩公共 API 或拆分大型模块。

## Acceptance Criteria

- [x] PowerShell 7.4+ 可成功通过目录与 manifest 两种规范方式导入，版本/edition 元数据一致。
- [x] 仓库不再有生产脚本或示例依赖空 `index.psm1`；`ai/downloadModels.ps1 -ListOnly` 不再因 psutils 命令缺失失败。
- [x] manifest 不包含不存在或重复覆盖的导出，每个关键公共函数的实际参数契约可由测试验证。
- [x] 直接导入存在跨模块调用的子模块时，依赖函数仍可见。
- [x] `pnpm --filter psutils test:qa`、`pnpm qa` 和 `pnpm test:pwsh:all` 通过。

## Out of Scope

- Windows PowerShell 5.1 legacy 包。
- 公共 API 全面重命名或删除。
- README 全量改写和模块职责重构。
- 删除 `index.psm1` 兼容 shim。

## Dependencies

- 无；本任务应作为首个实施子任务。
