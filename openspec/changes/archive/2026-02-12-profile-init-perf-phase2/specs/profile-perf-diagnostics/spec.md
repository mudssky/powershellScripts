## MODIFIED Requirements

### Requirement: 计时覆盖关键阶段

Profile 加载过程 SHALL 对关键阶段进行 `[System.Diagnostics.Stopwatch]` 精确计时，并将结果存入结构化变量 `$script:ProfileTimings`。

#### Scenario: 计时覆盖关键阶段

- **WHEN** Profile 以 Full 模式加载且 `POWERSHELL_PROFILE_TIMING=1`
- **THEN** SHALL 至少对以下阶段独立计时：模块加载、代理检测、UTF-8 编码设置、工具初始化（含 starship/zoxide 明细）、别名注册、总耗时

#### Scenario: starship 子步骤计时

- **WHEN** Profile 以 Full 模式加载且 starship 已安装
- **THEN** SHALL 对 starship init dot-source 单独计时，输出中 SHALL 可区分 starship 初始化耗时

#### Scenario: PSReadLine 键绑定计时

- **WHEN** Profile 以 Full 模式加载且 `POWERSHELL_PROFILE_TIMING=1`
- **THEN** 计时报告中 SHALL 不再包含 PSReadLine 键绑定的开销（因已移至 OnIdle，不在同步路径中）
