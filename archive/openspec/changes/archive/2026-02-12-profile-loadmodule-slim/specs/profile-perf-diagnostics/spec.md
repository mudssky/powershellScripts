## MODIFIED Requirements

### Requirement: 分阶段计时诊断

Profile 加载过程 SHALL 对关键阶段进行 `[System.Diagnostics.Stopwatch]` 精确计时。`Debug-ProfilePerformance.ps1` 的核心模块加载和代理检测步骤 SHALL 与 `profile.ps1` 实际加载逻辑保持一致。

#### Scenario: 诊断脚本核心模块列表与 profile 一致

- **WHEN** `Debug-ProfilePerformance.ps1` 执行 Phase 3 loadModule 步骤
- **THEN** SHALL 加载与 `core/loadModule.ps1` 相同的平台条件化模块列表（Windows: 4 个，Linux/macOS: 5 个）

#### Scenario: 诊断脚本代理缓存 TTL 与 profile 一致

- **WHEN** `Debug-ProfilePerformance.ps1` 执行 Phase 4 proxy-detect 步骤
- **THEN** SHALL 使用与 `features/environment.ps1` 相同的缓存 TTL 值

#### Scenario: 计时覆盖关键阶段

- **WHEN** Profile 以 Full 模式加载
- **THEN** SHALL 至少对以下阶段独立计时：模块加载、代理检测、工具初始化（含各工具明细）、别名注册、总耗时
