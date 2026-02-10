## Context

现有 `profile/profile.ps1` 在入口处先加载 `loadModule.ps1`，而 `loadModule.ps1` 会导入 `psutils` 的大量子模块。随后 `Initialize-Environment` 还会执行代理、路径同步、工具初始化与别名注册。

这套流程适合交互式开发，但不适合“短生命周期 + 受限环境”（如 Codex 沙盒、CI 执行器、一次性脚本）。

## Goals / Non-Goals

**Goals**
- 提供严格的“极简模式”，把 profile 初始化缩到最短路径
- 在极简模式中避免所有高风险外部依赖调用（shell 子进程、外部命令、代理探测）
- 保留最小但实用的会话能力（编码 + 根路径变量）

**Non-Goals**
- 不改变默认完整模式的行为
- 不在本次变更中重构 `psutils` 模块结构
- 不引入新依赖

## Decisions

1. **模式分层**
   - `Full`：当前默认行为
   - `Minimal`：现有轻量行为（保留兼容）
   - `UltraMinimal`：新增，强制走最短路径

### 分层语义对照（必须满足）

- `Full`
  - 适用场景：交互式日常开发
  - 行为：保持当前 profile 全能力

- `Minimal`
  - 适用场景：普通脚本执行、对启动速度有要求但仍需模块能力
  - 行为：
    - 保留：`psutils` 模块加载、UTF8、基础环境变量
    - 跳过：工具初始化、别名注册
    - 不保证跳过代理/PATH 同步（由参数或额外开关控制）

- `UltraMinimal`
  - 适用场景：Codex/CI/沙盒/一次性命令
  - 行为：
    - 仅保留：UTF8 + 基础兼容变量 + `POWERSHELL_SCRIPTS_ROOT`
    - 必须跳过：模块加载、代理、PATH 同步、工具初始化、别名/包装函数

2. **UltraMinimal 执行顺序**
   - 仅执行：
     1) `$IsWindows/$IsLinux/$IsMacOS` 兼容回退
     2) UTF8 编码配置
     3) `POWERSHELL_SCRIPTS_ROOT` 设置
   - 然后直接返回，不加载模块、不初始化工具

3. **触发条件（优先级）**
   - `POWERSHELL_PROFILE_FULL=1`：强制 Full
   - `POWERSHELL_PROFILE_MODE=ultra|minimal|full`：显式模式
   - `POWERSHELL_PROFILE_ULTRA_MINIMAL=1`：强制 UltraMinimal
   - 自动化环境探测（Codex/CI）默认映射为 `UltraMinimal`

4. **帮助函数降级策略**
   - 若未加载 `psutils`，`Show-MyProfileHelp` 仅显示“当前处于极简模式，已跳过高级功能加载”。

## Risks / Trade-offs

- 在极简模式下，用户会失去别名、包装函数、代理与工具增强能力。
- 某些依赖 profile 函数的旧脚本会因函数未加载而不可用（这是设计预期）。
- 需在文档中明确：极简模式面向“执行稳定与速度优先”。

## Validation Plan

- 启动耗时对比（Full vs UltraMinimal vs baseline）
- 验证极简模式下不触发外部工具初始化日志
- 验证 UTF8 与 `POWERSHELL_SCRIPTS_ROOT` 正常设置
