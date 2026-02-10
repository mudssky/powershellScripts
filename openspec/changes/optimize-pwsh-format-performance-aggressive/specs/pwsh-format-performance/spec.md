## ADDED Requirements

### Requirement: 未变更 Git 状态下的 Fast-path 早退
在 Git-changed mode 下运行时，formatter SHALL 在加载 formatter module 之前先计算变更的 PowerShell 文件，并且在没有符合条件的变更文件时 SHALL 立即退出。

#### Scenario: 无变更 PowerShell 文件
- **WHEN** 用户以 Git-changed mode 运行 format 命令，且仓库中不存在变更的 `.ps1` / `.psm1` / `.psd1` 文件
- **THEN** 命令在不导入 `PSScriptAnalyzer` 的情况下直接退出

### Requirement: 默认启用 aggressive formatter ruleset
formatter SHALL 默认使用显式的 aggressive ruleset；该规则集需排除高延迟的 casing correction 行为，同时保留核心 whitespace / indentation / brace formatting。

#### Scenario: 默认模式格式化
- **WHEN** 用户运行默认的 `format:pwsh` 命令
- **THEN** formatter 应用 aggressive ruleset，且不执行默认 full ruleset

### Requirement: 面向兼容性场景的 Strict mode
系统 SHALL 提供 strict mode，以便在兼容性敏感流程中应用完整的 formatter rule 行为。

#### Scenario: Strict mode 执行
- **WHEN** 用户运行 strict formatting 命令
- **THEN** formatter 应用 full/default rule 行为，并包含 casing correction

### Requirement: 低开销 module loading 策略
formatter SHALL 避免 module availability 预扫描，并 SHALL 直接尝试 module import；失败时通过安装指引或现有 install flow 处理。

#### Scenario: Module 已安装
- **WHEN** 格式化开始且所需 module 已存在
- **THEN** formatter 直接加载 module，不执行 `Get-Module -ListAvailable` 预扫描

### Requirement: 降低 startup 与 IO 开销
默认 npm formatter 命令 SHALL 使用 `pwsh -NoProfile`，且 formatter 实现 SHALL 通过 single-pass discovery 与 no-op write avoidance 降低 IO 成本。

#### Scenario: 格式化后内容未变化
- **WHEN** 文件的 formatted output 与原始内容完全一致
- **THEN** formatter 不重写该文件
