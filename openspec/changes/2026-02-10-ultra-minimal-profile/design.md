## Context

现有 `profile/profile.ps1` 在入口处先加载 `loadModule.ps1`，而 `loadModule.ps1` 会导入 `psutils` 的大量子模块。随后 `Initialize-Environment` 还会执行代理、路径同步、工具初始化与别名注册。

这套流程适合交互式开发，但不适合“短生命周期 + 受限环境”（如 Codex 沙盒、一次性脚本）。

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
  - 适用场景：脚本执行且需要使用模块函数
  - 行为：
    - 保留：`psutils` 模块加载、UTF8、基础环境变量
    - 跳过：工具初始化、别名注册
    - 不保证跳过代理/PATH 同步（由参数或额外开关控制）
  - 触发方式：仅手动显式指定（不自动触发）

- `UltraMinimal`
  - 适用场景：Codex/沙盒/一次性命令
  - 行为：
    - 仅保留：UTF8 + 基础兼容变量 + `POWERSHELL_SCRIPTS_ROOT`
    - 必须跳过：模块加载、代理、PATH 同步、工具初始化、别名/包装函数
  - 触发方式：显式指定，或自动环境探测命中 Codex/沙盒

2. **UltraMinimal 执行顺序**
   - 仅执行：
     1) `$IsWindows/$IsLinux/$IsMacOS` 兼容回退
     2) UTF8 编码配置
     3) `POWERSHELL_SCRIPTS_ROOT` 设置
   - 然后直接返回，不加载模块、不初始化工具

3. **触发条件（优先级）**
   - `POWERSHELL_PROFILE_FULL=1`：强制 Full（最高优先级）
   - `POWERSHELL_PROFILE_MODE=ultra|minimal|full`：显式模式
   - `POWERSHELL_PROFILE_ULTRA_MINIMAL=1`：强制 UltraMinimal
   - 自动环境探测仅在 Codex/沙盒命中时映射为 `UltraMinimal`
     - V1 最小变量集合：`CODEX_THREAD_ID` 或 `CODEX_SANDBOX_NETWORK_DISABLED`
     - `CODEX_MANAGED_BY_NPM/BUN` 不参与自动判定（仅用于诊断信息）
   - 默认模式为 `Full`

4. **当前范围约束（YAGNI）**
   - 当前不引入 CI 自动判定与自动降级逻辑
   - 后续如出现 CI 需求，再扩展判定矩阵

5. **帮助函数降级策略**
   - 若未加载 `psutils`，`Show-MyProfileHelp` 仅显示“当前处于极简模式，已跳过高级功能加载”。

6. **误判/漏判与诊断策略**
   - 诊断分层：
     - 基础版（V1）：先保证稳定可观测
     - 增强版（V2）：在不影响默认体验前提下补充更细指标
   - 模式决策可观测：
     - 在 `Verbose` 模式下输出单行决策摘要（最终模式 + 决策来源 + 命中的变量）
     - V1 建议格式：`[ProfileMode] mode=UltraMinimal source=auto reason=auto_codex_thread markers=CODEX_THREAD_ID elapsed_ms=128`
     - V2 可选扩展：`phase_ms`、`ps_version`、`host`、`pid`
   - 字段约定：
     - V1 必选：`mode`、`source`、`reason`、`markers`
     - V1 推荐：`elapsed_ms`
     - V2 扩展：`phase_ms`、`ps_version`、`host`、`pid`
   - `reason` 枚举（固定值）：
     - `explicit_full`
     - `explicit_mode_full`
     - `explicit_mode_minimal`
     - `explicit_mode_ultra`
     - `explicit_ultra_minimal`
     - `auto_codex_thread`
     - `auto_codex_sandbox_network_disabled`
     - `default_full`
   - `markers` 输出策略：
     - V1 输出全部命中变量（非首个命中）
     - 日志中允许出现未参与判定的参考变量，但须以 `diag_only` 标记
   - 手动兜底（用户可立即修正）：
     - 误判为 `UltraMinimal`：通过 `POWERSHELL_PROFILE_FULL=1` 强制回到 `Full`
     - 漏判未降级：通过 `POWERSHELL_PROFILE_MODE=ultra` 或 `POWERSHELL_PROFILE_ULTRA_MINIMAL=1` 强制极简
     - 需要函数但不要交互增强：通过 `POWERSHELL_PROFILE_MODE=minimal` 显式进入 `Minimal`
   - 规则透明化：
     - 仅声明并检测 V1 变量集合（`CODEX_THREAD_ID` / `CODEX_SANDBOX_NETWORK_DISABLED`）
     - 未纳入判定的变量（如 `CODEX_MANAGED_BY_NPM/BUN`）在日志中可显示，但不参与决策
   - 安全回退原则：
     - 无法判定或信息不足时，回退到默认 `Full`（避免错误降级导致功能缺失）

## Risks / Trade-offs

- 在极简模式下，用户会失去别名、包装函数、代理与工具增强能力。
- 某些依赖 profile 函数的旧脚本会因函数未加载而不可用（这是设计预期）。
- 需在文档中明确：极简模式面向“执行稳定与速度优先”。

## Validation Plan

- 启动耗时对比（Full vs UltraMinimal vs baseline）
- 验证极简模式下不触发外部工具初始化日志
- 验证 UTF8 与 `POWERSHELL_SCRIPTS_ROOT` 正常设置
- 验证决策摘要日志与手动兜底开关按优先级生效
