## Why

Phase 1 优化（psutils 分层延迟加载）已将 `core-loaders` 从 680ms 降至 ~290ms。但 `initialize-environment` 阶段仍耗时 ~780ms（Windows），精确诊断揭示两个此前未发现的大瓶颈：

1. **starship init dot-source 时执行 `Invoke-Native` 子进程**（~270ms）：缓存脚本中 `Set-PSReadLineOption -ContinuationPrompt (Invoke-Native ...)` 每次启动都 spawn starship 进程获取续行提示符，且跨平台缓存文件导致可执行路径错误。
2. **`Set-PSReadLineKeyHandler` 触发 PSReadLine 冷启动**（~260ms）：`encoding.ps1` 中的 Tab 补全键绑定注册触发 PSReadLine 模块的首次完整初始化。

两者合计 ~530ms，占 `initialize-environment` 的 **90%**。优化后预计可将总 profile 加载时间从 ~1150ms 降至 ~750ms。

## What Changes

- 将 `Set-PSReadLineKeyHandler -Key Tab` 从 `encoding.ps1` 同步路径移至 OnIdle 延迟注册
- 缓存 starship `prompt --continuation` 的输出，避免每次启动都 spawn 外部进程
- 确保 starship 缓存文件按平台区分，防止 Linux/Windows 交叉污染

## Capabilities

### New Capabilities
- `psreadline-deferred-init`: PSReadLine 键绑定延迟到 OnIdle 注册，避免触发 PSReadLine 冷启动开销
- `starship-continuation-cache`: 缓存 starship continuation prompt 输出，消除每次启动的子进程调用

### Modified Capabilities
- `profile-perf-diagnostics`: 在分阶段计时中新增 starship/PSReadLine 的细粒度子步骤计时

## Impact

- 修改文件：`profile/core/encoding.ps1`、`profile/core/loadModule.ps1`、`profile/features/environment.ps1`
- 新增缓存文件：`profile/.cache/starship-continuation-<platform>.ps1`（自动生成）
- 影响范围：仅 profile 启动路径，不影响运行时行为
- 风险：OnIdle 触发前用户按 Tab 将使用 PowerShell 默认补全行为（`TabCompleteNext` 而非 `Complete`），实际影响极小
