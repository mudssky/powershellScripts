## ADDED Requirements

### Requirement: Rust formatter CLI entrypoint
系统 SHALL 提供 `pwshfmt-rs` CLI，用于处理 PowerShell 文件格式化辅助流程。

#### Scenario: CLI 参数解析成功
- **WHEN** 用户运行 `pwshfmt-rs --help`
- **THEN** CLI 展示可用参数并返回成功退出码

### Requirement: Git changed fast-path
`pwshfmt-rs` SHALL 支持 `--git-changed` 模式，仅处理 Git 改动的 `.ps1` / `.psm1` / `.psd1` 文件。

#### Scenario: 无改动文件时快速退出
- **WHEN** 用户运行 `pwshfmt-rs --git-changed --check` 且不存在改动的 PowerShell 文件
- **THEN** 工具不进入文件处理阶段并快速成功退出

### Requirement: Check and write modes
`pwshfmt-rs` SHALL 同时支持 `--check` 与 `--write` 模式。

#### Scenario: Check 模式发现可修复内容
- **WHEN** 用户运行 `pwshfmt-rs --check` 且存在 casing 可修复项
- **THEN** 工具返回非零退出码并输出待修复摘要

#### Scenario: Write 模式执行修复
- **WHEN** 用户运行 `pwshfmt-rs --write` 且存在 casing 可修复项
- **THEN** 工具写回修复后的文件并输出修复统计

### Requirement: Casing correction subset
`pwshfmt-rs` SHALL 至少支持命令名与参数名的 casing correction，并避免修改字符串字面量与注释内容。

#### Scenario: 修复命令与参数大小写
- **WHEN** 文件中出现非规范大小写的 cmdlet 与参数名
- **THEN** 工具将其修正为规范大小写且不改动注释与字符串文本

### Requirement: No-op write avoidance
`pwshfmt-rs` SHALL 在格式化结果与原文件一致时跳过写盘。

#### Scenario: 内容无变化
- **WHEN** 工具处理文件后结果与原始内容完全一致
- **THEN** 工具不重写该文件

### Requirement: Strict fallback compatibility
`pwshfmt-rs` SHALL 提供 `--strict-fallback` 能力，在无法安全处理的场景下回退到现有严格格式化链路。

#### Scenario: 遇到不安全改写场景
- **WHEN** 工具检测到动态调用或无法可靠定位的 token 场景
- **THEN** 工具按配置调用严格链路并记录回退信息
