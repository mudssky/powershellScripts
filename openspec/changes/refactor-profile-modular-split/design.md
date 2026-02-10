## Context

当前 `profile/profile.ps1` 已同时承载模式决策、扩展脚本加载、环境初始化、帮助输出与安装入口，文件复杂度持续增长。近期又引入 `UltraMinimal` 相关逻辑，进一步增加了维护与回归风险。

本变更目标是将实现按职责拆分到子脚本，同时保持统一入口与既有外部行为不变。

## Goals / Non-Goals

**Goals:**
- 将 `profile/profile.ps1` 拆分为入口编排 + 职责模块，降低维护复杂度。
- 保持 `Full/Minimal/UltraMinimal` 的语义、优先级与日志输出行为兼容。
- 保持 `Show-MyProfileHelp`、`Initialize-Environment`、`Set-PowerShellProfile` 的可见性与调用方式兼容。
- 采用“先 pure refactor，再单独优化”的策略，降低回归风险。

**Non-Goals:**
- 不新增功能，不改变对外参数接口。
- 不在本次拆分中引入性能优化或行为修正。
- 不修改 `profile_unix.ps1` 的 shim 语义。

## Decisions

1. **入口文件最小化**
   - `profile/profile.ps1` 保留参数、PS 5.1 兼容回退、主流程编排、耗时统计。
   - 业务逻辑迁移到 `profile/core/*.ps1` 与 `profile/features/*.ps1`。

2. **按职责拆分模块**
   - `profile/core/mode.ps1`：环境开关解析、模式决策、决策摘要与兜底提示。
   - `profile/core/encoding.ps1`：UTF8 编码设置。
   - `profile/core/loaders.ps1`：`loadModule.ps1` / `wrapper.ps1` / `user_aliases.ps1` 条件加载。
   - `profile/features/environment.ps1`：`Initialize-Environment`。
   - `profile/features/help.ps1`：`Show-MyProfileHelp`。
   - `profile/features/install.ps1`：`Set-PowerShellProfile` 与安装相关逻辑。

3. **固定 dot-source 顺序**
   - 顺序：`core`（基础函数）→ `mode`（决策）→ `core/loaders`（按模式加载扩展）→ `features`（对外函数）→ 主执行逻辑。
   - 目标是避免“函数未定义”与脚本作用域变量未初始化的问题。

4. **兼容优先策略**
   - 拆分过程采用“代码搬迁 + 最小胶水”，不修改现有行为分支。
   - 所有模式相关变量保持原脚本作用域命名，减少连带修改。

## Risks / Trade-offs

- **[风险] dot-source 顺序变更导致运行期函数缺失** → **缓解**：在入口文件固化顺序，并用 `pwsh -NoProfile` 做回归验证。
- **[风险] 作用域变化导致 `$script:*` 变量不可见** → **缓解**：统一使用脚本作用域变量并在入口初始化。
- **[权衡] 文件数增加提高导航成本** → **缓解**：以 `core/features` 双层命名保持可发现性。

## Migration Plan

1. 新建目标脚本文件并迁移函数（先不改逻辑）。
2. 在 `profile/profile.ps1` 接入新的 dot-source 编排。
3. 运行三种模式回归（Full/Minimal/UltraMinimal）与帮助函数回归。
4. 若回归失败，回滚到单文件版本并逐模块重试迁移。

## Open Questions

- 当前无阻塞问题；若后续出现跨文件共享状态混乱，再评估引入统一上下文对象。
