## ADDED Requirements

### Requirement: 缓存 starship continuation prompt 输出

Profile SHALL 使用 `Invoke-WithFileCache` 缓存 `starship prompt --continuation` 命令的输出，避免每次启动都 spawn starship 子进程。

#### Scenario: 缓存命中时不启动子进程

- **WHEN** starship init 缓存文件存在且未过期，且 continuation prompt 缓存存在且未过期
- **THEN** `Set-PSReadLineOption -ContinuationPrompt` SHALL 使用缓存的字面量值，SHALL NOT 调用 `Invoke-Native` 或启动任何外部进程

#### Scenario: 缓存未命中时生成并存储

- **WHEN** continuation prompt 缓存文件不存在或已过期
- **THEN** SHALL 调用 `starship prompt --continuation` 获取输出，将结果写入缓存文件，有效期 SHALL 为 7 天

#### Scenario: 缓存有效期与 starship init 一致

- **WHEN** starship init 缓存重新生成（因过期或手动删除）
- **THEN** continuation prompt 缓存 SHALL 同时失效并重新生成

### Requirement: starship 缓存按平台隔离

starship init 缓存文件 SHALL 按运行平台区分 key，防止跨平台项目共享时缓存交叉污染。

#### Scenario: Windows 使用 Windows 专用缓存

- **WHEN** profile 在 Windows 上加载且 starship 缓存不存在
- **THEN** SHALL 生成 key 包含 `win` 标识的缓存文件，`Invoke-Native` 中的可执行路径 SHALL 指向 Windows 的 starship.exe

#### Scenario: Linux 使用 Linux 专用缓存

- **WHEN** profile 在 Linux 上加载且 starship 缓存不存在
- **THEN** SHALL 生成 key 包含 `linux` 标识的缓存文件

#### Scenario: 旧的无平台标识缓存被忽略

- **WHEN** 存在旧的 `starship-init-powershell.ps1` 缓存文件（无平台标识）
- **THEN** SHALL 不使用该文件，SHALL 生成新的平台专用缓存

### Requirement: post-processing 失败时保持原始行为

对 starship init 缓存脚本的 post-processing（替换 `Invoke-Native` 为缓存值）SHALL 实现 fallback 机制。

#### Scenario: 正则替换成功

- **WHEN** starship init 输出中包含 `Set-PSReadLineOption -ContinuationPrompt (Invoke-Native ...)`
- **THEN** SHALL 将 `Invoke-Native` 调用替换为缓存的字面量字符串

#### Scenario: 正则替换失败时保持原样

- **WHEN** starship init 输出格式不匹配预期的正则模式（如 starship 版本更新）
- **THEN** SHALL 保留原始 `Invoke-Native` 调用不做修改，通过 `Write-Verbose` 记录替换失败
