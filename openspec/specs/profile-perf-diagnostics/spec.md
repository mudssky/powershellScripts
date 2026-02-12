## ADDED Requirements

### Requirement: 分阶段计时诊断

Profile 加载过程 SHALL 对关键阶段进行 `[System.Diagnostics.Stopwatch]` 精确计时，并将结果存入结构化变量 `$script:ProfileTimings`。

#### Scenario: 默认 Verbose 输出

- **WHEN** Profile 加载完成且未设置 `POWERSHELL_PROFILE_TIMING` 环境变量
- **THEN** 各阶段耗时 SHALL 仅通过 `Write-Verbose` 输出，不影响正常终端显示

#### Scenario: 环境变量启用详细计时

- **WHEN** `POWERSHELL_PROFILE_TIMING=1` 且 Profile 加载完成
- **THEN** SHALL 在终端输出各阶段耗时报告，格式包含阶段名称和毫秒数

#### Scenario: 计时覆盖关键阶段

- **WHEN** Profile 以 Full 模式加载且 `POWERSHELL_PROFILE_TIMING=1`
- **THEN** SHALL 至少对以下阶段独立计时：模块加载、代理检测、UTF-8 编码设置、工具初始化（含 starship/zoxide 明细）、别名注册、总耗时

#### Scenario: starship 子步骤计时

- **WHEN** Profile 以 Full 模式加载且 starship 已安装
- **THEN** SHALL 对 starship init dot-source 单独计时，输出中 SHALL 可区分 starship 初始化耗时

#### Scenario: PSReadLine 键绑定计时

- **WHEN** Profile 以 Full 模式加载且 `POWERSHELL_PROFILE_TIMING=1`
- **THEN** 计时报告中 SHALL 不再包含 PSReadLine 键绑定的开销（因已移至 OnIdle，不在同步路径中）

#### Scenario: 诊断脚本核心模块列表与 profile 一致

- **WHEN** `Debug-ProfilePerformance.ps1` 执行 Phase 3 loadModule 步骤
- **THEN** SHALL 加载与 `core/loadModule.ps1` 相同的平台条件化模块列表（Windows: 4 个，Linux/macOS: 5 个）

#### Scenario: 诊断脚本代理缓存 TTL 与 profile 一致

- **WHEN** `Debug-ProfilePerformance.ps1` 执行 Phase 4 proxy-detect 步骤
- **THEN** SHALL 使用与 `features/environment.ps1` 相同的缓存 TTL 值

#### Scenario: 计时开销可忽略

- **WHEN** Profile 加载
- **THEN** 计时机制本身的开销 SHALL 不超过 5ms
