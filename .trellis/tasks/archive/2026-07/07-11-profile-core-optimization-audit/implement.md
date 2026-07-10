# Profile Core 优化实施计划

## Implementation Order

- [x] 1. 建立可相信的实施前后测量
  - 记录当前 macOS/Pwsh 环境与 PRD 中的三模式基线。
  - 为真实入口增加结构化计时输出契约。
  - 重写 `Debug-ProfilePerformance.ps1` 为真实入口的新进程采样驱动器，保留现有隔离参数。
  - 先补诊断契约测试，确保模式和阶段数据来自真实入口。

- [x] 2. 提取 bootstrap 与平台上下文
  - 新增 `profile/core/bootstrap.ps1`，迁移 PATH helper 并实现最小初始化。
  - 新增 `profile/core/platform.ps1`，实现可注入平台的纯上下文函数。
  - 补 Windows/macOS/Linux 上下文矩阵测试。

- [x] 3. 调整主入口的模式分流
  - `profile.ps1` 只先加载 bootstrap、mode、platform 与轻量 Help/Install 兼容定义。
  - 在 UltraMinimal 分支执行最小初始化、写计时结果并返回。
  - Full/Minimal 再加载 loaders、environment、help、install。
  - 为必需与可选定义应用分级错误处理。

- [x] 4. 重构核心加载器与 OnIdle 生命周期
  - 将 `core/loadModule.ps1` 顶层逻辑改为可测试函数。
  - 将 `core/loaders.ps1` 脚本块改为 `Invoke-ProfileCoreLoaders`。
  - Full/Minimal 保持同步核心模块；仅 Full 读取别名配置。
  - 实现 OnIdle 订阅/状态幂等，补连续加载与失败隔离测试。
  - 更新 `profile/loadModule.ps1` 兼容 shim。

- [x] 5. 清除 Minimal 无效工作并集中平台消费
  - `Initialize-Environment` 接收模式和平台上下文。
  - Minimal 在公共环境初始化后提前返回。
  - 工具集合、包管理器、缓存 ID、PATH 同步和路径比较使用平台上下文。
  - 验证 Minimal 不执行别名读取或工具探测，同时核心模块立即可用。

- [x] 6. 实现分级降级
  - bootstrap/mode/platform 失败明确终止。
  - 核心模块、必需 feature 或完整环境失败时输出原始错误并降级到 UltraMinimal。
  - Help、Install、别名、OnIdle 单项失败按设计告警并继续。
  - 增加失败组件与最终模式断言。

- [x] 7. 同步测试与文档
  - 更新 `ProfileMode.Tests.ps1`、`DeferredLoading.Tests.ps1`，按需要新增 Profile 平台/加载/诊断测试文件。
  - 更新 README 的目标加载流程、模式语义、核心模块数量、OnIdle 用法和性能诊断命令。
  - 为所有新增或修改函数补齐中文 comment-based help、参数与返回值说明。

- [x] 8. 全量验证与回归比较
  - 运行窄范围 Profile Pester 测试。
  - 运行 `pnpm qa`。
  - 运行 `pnpm test:pwsh:all`；Docker 不可用时至少运行 `pnpm test:pwsh:full` 并记录平台限制。
  - 在 macOS 上按 Full/Minimal/UltraMinimal 交替采样至少 5 次，输出前后统计与限制。
  - 检查工作区，只纳入本任务相关文件，不触碰现有无关改动。

## Validation Commands

```powershell
# Profile 相关窄测；实施时按最终测试文件名调整路径列表
pwsh -NoProfile -NoLogo -Command "Invoke-Pester -Path './tests/ProfileMode.Tests.ps1','./tests/DeferredLoading.Tests.ps1','./tests/ProfileLoading.Tests.ps1'"

# 工程质量与 PowerShell 全量回归
pnpm qa
pnpm test:pwsh:all

# 真实入口多样本性能诊断；参数以最终实现为准
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode Full -Iterations 5
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode Minimal -Iterations 5
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode UltraMinimal -Iterations 5
```

## Risky Files And Rollback Points

- `profile/profile.ps1`：启动链核心；每次调整加载顺序后立即跑三模式子进程 smoke test。
- `profile/core/loadModule.ps1`：模块作用域与 OnIdle 事件复杂；先保留兼容 shim，再替换调用方。
- `profile/features/environment.ps1`：Full 用户行为集中；Minimal 提前返回必须位于代理/env/编码之后、工具探测之前。
- `profile/Debug-ProfilePerformance.ps1`：先建立结构化契约测试，再移除旧的手工重放逻辑。
- 若某阶段失败，按“诊断 -> bootstrap/platform -> early split -> loaders/OnIdle -> environment”逆序回退，不回退用户现有无关修改。

## Review Gates Before `task.py start`

- [x] 用户确认“不拆入口、集中平台策略”的设计。
- [x] 用户确认 Minimal 保持核心模块立即可用。
- [x] 用户确认分级降级策略。
- [x] 用户确认第一轮不全面重写 `mode.ps1`。
- [x] 用户审核本 PRD、设计和实施顺序，并明确批准进入实现阶段。

## Verification Results

- macOS Profile 窄测：28 passed / 0 failed。
- Linux Docker Profile 窄测：28 passed / 0 failed。
- `pnpm qa`：123 passed / 0 failed / 6 not run。
- `pnpm test:pwsh:all`：宿主 654 passed / 0 failed；Linux 655 passed / 1 failed。唯一失败为任务开始前已有改动 `Switch-Mirrors.Tests.ps1` 的官方仓库探活断言，与 Profile 文件无调用关系。
- 2026-07-11 macOS / PowerShell 7.5.4，每种模式 5 个新进程交替采样：
  - Full：Profile internal 中位数 417ms，Process elapsed 中位数 688ms。
  - Minimal：Profile internal 中位数 236ms，Process elapsed 中位数 503ms。
  - UltraMinimal：Profile internal 中位数 189ms，Process elapsed 中位数 452ms。
- 相对同机实施前内部中位数：Full +1.5%，Minimal -18.6%，UltraMinimal -5.5%。
