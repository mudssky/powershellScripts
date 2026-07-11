## Why

Windows 环境下 Profile 加载耗时从约 1s 增长到约 2s，且 Tab 补全响应变慢（需数秒才能返回候选）。经分析，加载瓶颈集中在代理 TCP 探测阻塞、`Test-EXEProgram` 多次扫描 PATH、`Get-Command` 搜索范围过宽等问题；Tab 补全慢的根因是 starship 初始化脚本缓存形同虚设（缓存的是引导代码而非完整初始化脚本，导致每次 prompt 渲染都 spawn 外部进程）以及 `MenuComplete` 模式要求一次性枚举所有候选。需要在不破坏现有功能和模式语义的前提下，将 Full 模式加载时间降回 1s 以内，并显著改善 Tab 补全响应速度。

## What Changes

- 修复 starship 初始化脚本的 `Invoke-WithFileCache` 缓存，使用 `--print-full-init` 缓存完整初始化脚本而非引导代码，消除每次 prompt 渲染 spawn starship 进程的问题
- 将 Tab 补全模式从 `MenuComplete` 切换回 `Complete`，避免一次性枚举所有候选的开销
- 优化 `Initialize-Environment` 中的工具检测逻辑，用批量 `Get-Command` 替代逐个 `Test-EXEProgram` 调用
- 优化 `Set-Proxy -Command auto` 的 TCP 探测，缩短超时并考虑缓存上次代理状态
- 优化 `Set-ProfileUtf8Encoding` 中的 `Get-Command` 调用，缩窄搜索范围
- 精简 PSModulePath，不添加不必要的额外模块搜索路径
- 为 `Initialize-Environment` 添加分阶段计时诊断，便于后续持续监控性能回归

## Capabilities

### New Capabilities

- `profile-perf-diagnostics`: Profile 加载分阶段计时诊断能力，提供每个阶段的耗时报告

### Modified Capabilities

- `unified-profile`: 修复 starship 缓存、切换 Tab 补全模式、优化工具初始化流程和代理检测逻辑、精简 PSModulePath

## Impact

- **profile/features/environment.ps1**: `Initialize-Environment` 函数修复 starship 缓存参数、重构工具检测和代理探测逻辑
- **profile/core/encoding.ps1**: `Set-ProfileUtf8Encoding` 函数切换 Tab 补全模式并优化 `Get-Command` 调用
- **profile/core/loadModule.ps1**: 精简 PSModulePath 操作
- **psutils/modules/proxy.psm1**: `Set-Proxy auto` 优化 TCP 超时
- **profile/profile.ps1**: 添加分阶段计时支持
