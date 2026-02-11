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

- **WHEN** Profile 以 Full 模式加载
- **THEN** SHALL 至少对以下阶段独立计时：模块加载、代理检测、工具初始化（含各工具明细）、别名注册、总耗时

#### Scenario: 计时开销可忽略

- **WHEN** Profile 加载
- **THEN** 计时机制本身的开销 SHALL 不超过 5ms
