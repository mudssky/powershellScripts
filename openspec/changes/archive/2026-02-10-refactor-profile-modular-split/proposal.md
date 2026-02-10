## Why

当前 `profile/profile.ps1` 已承担过多职责（模式决策、模块加载、环境初始化、帮助输出、安装入口），文件持续增长，导致维护成本上升、评审困难、回归范围扩大。现在推进“结构拆分但行为不变”可以降低后续改动风险，并为后续性能优化与故障定位提供更清晰边界。

## What Changes

- 将 `profile/profile.ps1` 拆分为“入口编排 + 职责模块”，按职责迁移到子脚本文件。
- 保持对外调用方式不变（继续支持 `./profile.ps1` 与现有参数）。
- 保持 `Full/Minimal/UltraMinimal` 模式语义与优先级规则不变。
- 保持 `Show-MyProfileHelp`、`Initialize-Environment`、`Set-PowerShellProfile` 的可用性和兼容行为。
- 明确拆分边界：先做 pure refactor（不引入行为变化），后续优化另行提案。

## Capabilities

### New Capabilities
- 无

### Modified Capabilities
- `unified-profile`: 增加“模块化拆分与入口稳定性”要求，确保拆分后外部行为与加载语义保持一致。

## Impact

- **影响代码**: `profile/profile.ps1`，新增 `profile/core/*.ps1` 与 `profile/features/*.ps1`（命名以实现阶段为准）。
- **行为影响**: 目标为 0 行为变化（仅代码组织调整）。
- **风险**: dot-source 顺序或作用域处理不当可能引入隐性回归。
- **验证重点**: 三种模式加载路径、关键函数可见性、参数兼容性、启动耗时回归。
