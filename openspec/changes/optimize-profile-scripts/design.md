## Context

当前 profile 体系由 `profile.ps1` 统一入口加载 `loadModule.ps1`、`wrapper.ps1`、`user_aliases.ps1`。
整体功能稳定，但存在一些“易碎点”与维护成本：
- 模块导入或 dot-source 失败时，错误上下文不够清晰
- 工具探测函数命名不一致（`Test-EXEProgram` / `Test-ExeProgram`），可能导致误判
- 别名函数通过字符串拼接生成脚本块，复杂参数/引号场景易出错
- 低频但会累积的问题（`PSModulePath` 重复、`Get-Help` 性能）

本次优化在保持行为一致的前提下，提升可维护性与错误可定位性。

## Goals / Non-Goals

**Goals:**
- 保留现有行为与外部接口，仅增强错误上下文与健壮性
- 统一工具探测函数命名，避免误判
- 别名执行方式改为结构化调用，减少参数解析风险
- 低风险维护性提升（可选）：`PSModulePath` 去重、`Get-Help` 缓存

**Non-Goals:**
- 不引入新的依赖或新的功能特性
- 不改变加载入口、模块组织或文件路径
- 不增加路径存在性检查（已确认路径稳定）
- 不重写 alias 体系或 wrapper 函数的业务逻辑

## Decisions

- **最小化错误上下文**：
  - `loadModule.ps1` 的 `Import-Module` 使用 `try/catch`，失败时输出清晰来源（模块名/路径）
  - `profile.ps1` 对 dot-source 的三个脚本使用轻量 `try/catch`，不做 `Test-Path`

- **统一工具探测函数**：
  - 以 `psutils` 模块实际暴露的函数名为准，统一脚本中的调用写法

- **别名执行改为结构化调用**：
  - `user_aliases.ps1` 中将 `command` 拆为 `command` + `commandArgs`（数组）
  - `Set-AliasProfile` 中使用 `& $command @commandArgs @($args)` 执行
  - 不再依赖字符串拼接，避免引号/空格导致的解析问题

- **低风险维护性提升（可选项）**：
  - `PSModulePath` 做去重
  - `Get-Help` 结果缓存（与现有 `Invoke-WithFileCache` 风格保持一致）

## Risks / Trade-offs

- **别名结构变化的迁移成本**：需要同步调整 `user_aliases.ps1` 的对象结构，否则新逻辑无法识别
- **错误提示变更**：输出更明确但也可能更“啰嗦”，需控制在最小可读范围
- **不做路径检查**：保留简洁性，但路径意外变动时的保护较弱（已接受）
