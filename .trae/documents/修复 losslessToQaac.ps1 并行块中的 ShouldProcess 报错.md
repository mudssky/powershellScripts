## 背景与原因
- 报错来源：`You cannot call a method on a null-valued expression` 出现在并行脚本块中调用 `$PSCmdlet.ShouldProcess(...)`。
- 根因解释：`ForEach-Object -Parallel` 在独立 Runspace 中执行，**不携带调用者的 Cmdlet 上下文**，因此 `$PSCmdlet` 在并行块内为 `null`，任何对 `ShouldProcess` 的调用都会触发上述错误。
- 代码定位：`c:\home\env\powershellScripts\losslessToQaac.ps1:133` 使用了 `$PSCmdlet.ShouldProcess($escapedAudiofilePath, '转换为 m4a')`。

## 目标
- 保留脚本的 `-WhatIf` 语义（即启用 `SupportsShouldProcess` 带来的“预演”行为）。
- 修复并行转换与删除原文件的执行逻辑，不再依赖并行块内的 `$PSCmdlet`。
- 改善错误处理与健壮性，避免静默吞错影响排障。

## 变更方案
### 1) 用 `$using:WhatIfPreference` 代替并行块中的 `ShouldProcess`
- 在并行块中使用 `$using:WhatIfPreference` 作为布尔门控：
  - 若为 `True`：仅打印将要执行的命令（不实际执行），如 `WhatIf: would run qaac ...`。
  - 若为 `False`：实际执行 `Invoke-Expression $commandStr`。
- 同样对删除源文件（`Remove-Item`）做门控，`-WhatIf` 时不删除。

### 2) 提升健壮性与可观测性
- 将 `$ErrorActionPreference = 'Stop'` 与 `Set-StrictMode -Version Latest` 移至脚本开头，使错误立即失败、便于定位。
- 在并行块内包一层 `try { ... } catch { ... }`，输出包含文件路径的上下文错误消息；失败时保持进度统计一致。
- 保留当前对命令输出的抑制，但在失败分支打印简要提示，避免完全静默。

### 3) 文档与注释
- 在头部 `.NOTES` 增加说明：并行执行下使用 `$using:WhatIfPreference` 提供 “预演（WhatIf）” 行为。
- 参数与示例不变；在示例中补充 `-WhatIf` 预演用法。

## 验证方案（不执行写操作，仅说明）
- 干跑验证：运行 `.\losslessToQaac.ps1 -WhatIf`，观察：
  - 不应再出现 `$PSCmdlet` 相关报错。
  - 控制台打印每个文件的 `WhatIf: would run qaac ...` 与不删除源文件的提示。
- 实跑验证：在包含 1–2 个测试文件的临时目录上运行不带 `-WhatIf` 的脚本，确认：
  - 新的 `.m4a` 文件能够生成；
  - 在未指定 `-nodelete` 时源文件被删除；
  - 进度统计与最终耗时打印正常。

## 影响面与风险
- 修改文件：`c:\home\env\powershellScripts\losslessToQaac.ps1`。
- 风险：
  - 将严格模式与 Stop 策略前移可能暴露更多潜在脚本问题（有利于早期发现）。
  - `-WhatIf` 语义从 `ShouldProcess` 切换为偏好变量门控，但对脚本而言效果等价。

## 下一步
- 我将按上述方案更新脚本，移除并行块中的 `$PSCmdlet.ShouldProcess`，改用 `$using:WhatIfPreference` 并补充错误处理与文档说明。请确认是否按该方案进行修改。