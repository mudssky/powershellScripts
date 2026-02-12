## ADDED Requirements

### Requirement: PSReadLine Tab 键绑定延迟注册

`encoding.ps1` 中的 `Set-PSReadLineKeyHandler -Key Tab -Function Complete` SHALL 从同步路径移除，改为在 OnIdle 事件中延迟执行。

#### Scenario: 同步路径不触发 PSReadLine 初始化

- **WHEN** profile 以 Full 模式加载并执行 `Set-ProfileUtf8Encoding`
- **THEN** SHALL NOT 调用 `Set-PSReadLineKeyHandler`，PSReadLine 模块 SHALL NOT 被强制初始化

#### Scenario: OnIdle 触发后 Tab 补全为 Complete 模式

- **WHEN** OnIdle 事件触发并执行键绑定注册
- **THEN** Tab 键 SHALL 绑定到 `Complete` 函数（菜单补全模式）

#### Scenario: OnIdle 触发前 Tab 使用 PowerShell 默认行为

- **WHEN** 用户在 OnIdle 触发前按下 Tab 键
- **THEN** SHALL 使用 PowerShell 默认的 `TabCompleteNext` 行为（循环补全），不产生错误

#### Scenario: 键绑定注册失败不影响终端

- **WHEN** OnIdle 事件中 `Set-PSReadLineKeyHandler` 调用失败
- **THEN** SHALL 通过 `Write-Warning` 静默记录错误，终端 SHALL 继续正常工作

### Requirement: 编码设置保留在同步路径

`Set-ProfileUtf8Encoding` 中的 UTF-8 编码设置（`[Console]::OutputEncoding`、`$Global:OutputEncoding`、`PSDefaultParameterValues["Out-File:Encoding"]`）SHALL 保留在同步路径中执行，不延迟。

#### Scenario: 编码在 prompt 显示前已生效

- **WHEN** profile 加载完成并显示首个 prompt
- **THEN** 控制台输出编码 SHALL 为 UTF-8 (No BOM)
