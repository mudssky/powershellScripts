## ADDED Requirements

### Requirement: Rust formatter CLI entrypoint
系统 SHALL 提供 `pwshfmt-rs` CLI，用于处理 PowerShell 文件格式化辅助流程。

#### Scenario: CLI 可用性
- **WHEN** 用户运行 `pwshfmt-rs --help`
- **THEN** CLI 展示可用命令与参数并返回成功退出码

### Requirement: Target selection
`pwshfmt-rs` SHALL 支持按 Git 改动与路径模式选择目标文件。

#### Scenario: Git 改动快速路径
- **WHEN** 用户运行 Git 改动模式且存在改动的 `.ps1` / `.psm1` / `.psd1` 文件
- **THEN** 工具仅处理这些改动文件

#### Scenario: 路径与模式匹配
- **WHEN** 用户提供路径或 glob 模式并启用递归扫描
- **THEN** 工具 SHALL 基于 `walkdir + globset` 发现匹配的 PowerShell 文件

### Requirement: Check and write modes
`pwshfmt-rs` SHALL 同时支持校验与写回两类执行模式。

#### Scenario: Check 模式发现可修复项
- **WHEN** 用户执行 check 模式且存在可修复内容
- **THEN** 工具返回非零退出码并输出待修复摘要

#### Scenario: Write 模式写回修复
- **WHEN** 用户执行 write 模式且存在可修复内容
- **THEN** 工具写回修复结果并输出修复统计

### Requirement: Casing correction subset
`pwshfmt-rs` SHALL 支持命令名与参数名的 casing correction，并避免修改字符串字面量与注释内容。

#### Scenario: 修复命令与参数大小写
- **WHEN** 文件中出现非规范大小写的 cmdlet 或参数名
- **THEN** 工具将其修正为规范大小写且不改动注释与字符串文本

### Requirement: No-op write avoidance
`pwshfmt-rs` SHALL 在格式化结果与原文件一致时跳过写盘。

#### Scenario: 内容无变化
- **WHEN** 文件格式化结果与原始内容完全一致
- **THEN** 工具不重写该文件

### Requirement: Strict fallback compatibility
`pwshfmt-rs` SHALL 提供 strict fallback 能力，在无法安全处理的场景下回退到严格链路。

#### Scenario: 触发不安全场景
- **WHEN** 工具检测到动态调用或无法可靠定位的 token 场景
- **THEN** 工具按配置调用严格链路并记录回退信息

### Requirement: Layered configuration with defaults
`pwshfmt-rs` SHALL 提供分层配置系统，优先级顺序为 `CLI > ENV > config file > built-in defaults`。

#### Scenario: 无配置文件默认可运行
- **WHEN** 未找到配置文件
- **THEN** 工具 SHALL 使用内置默认值成功执行

#### Scenario: CLI 覆盖低优先级来源
- **WHEN** 同一配置项同时出现在配置文件、环境变量与 CLI
- **THEN** 最终生效值 SHALL 使用 CLI 传入值

### Requirement: Unified diagnostic errors
`pwshfmt-rs` SHALL 通过 `miette` 输出统一诊断错误。

#### Scenario: 底层操作失败
- **WHEN** 文件系统或外部命令调用失败
- **THEN** 工具 SHALL 返回非零退出码并输出带上下文信息的 `miette` 诊断

### Requirement: Integration-test-first behavior coverage
`pwshfmt-rs` SHALL 以集成测试覆盖关键行为路径。

#### Scenario: 关键流程可回归
- **WHEN** 执行项目测试
- **THEN** 集成测试 SHALL 覆盖 CLI、配置优先级、check/write、fallback 与文件发现行为
