## 1. Tab 补全与 Prompt 性能修复

- [x] 1.1 在 `profile/features/environment.ps1` 中将 starship 的 `Invoke-WithFileCache` Generator 从 `{ & starship init powershell }` 改为 `{ & starship init powershell --print-full-init }`，使缓存包含完整初始化脚本
- [x] 1.2 删除现有的 `profile/.cache/starship-init-powershell.ps1` 缓存文件，强制下次加载时重建
- [x] 1.3 在 `profile/core/encoding.ps1` 中将 `Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete` 改为 `Set-PSReadLineKeyHandler -Key Tab -Function Complete`

## 2. 编码初始化优化

- [x] 2.1 在 `profile/core/encoding.ps1` 中移除 `Get-Command -Name Set-PSReadLineKeyHandler` 检查，直接调用 `Set-PSReadLineKeyHandler`（PowerShell 7+ 内置 PSReadLine）
- [x] 2.2 将 `Get-Command -Name Register-FzfHistorySmartKeyBinding` 改为 `Get-Command -Name Register-FzfHistorySmartKeyBinding -CommandType Function`

## 3. 工具检测批量化

- [x] 3.1 在 `profile/features/environment.ps1` 的 `Initialize-Environment` 中，将工具初始化循环前的逐个 `Test-EXEProgram` 替换为单次 `Get-Command -Name @('starship','zoxide','sccache','fnm') -CommandType Application` 批量查询
- [x] 3.2 将批量查询结果存入 HashSet，后续用 `$availableTools.Contains($name)` 替代 `Test-EXEProgram` 调用
- [x] 3.3 保留工具未安装时的提示逻辑不变

## 4. 代理探测优化

- [x] 4.1 在 `psutils/modules/proxy.psm1` 的 `Set-Proxy auto` 中将 TCP 超时从 100ms 缩短为 50ms
- [x] 4.2 在 `Set-Proxy on` 中移除二次端口检测（200ms timeout 的 TCP 连接），改为直接设置环境变量
- [x] 4.3 在 `Initialize-Environment` 中为 `Set-Proxy auto` 包装 `Invoke-WithCache` 缓存层，缓存有效期 5 分钟

## 5. PSModulePath 精简

- [x] 5.1 在 `profile/core/loadModule.ps1` 中移除将项目父目录 `$moduleParent` 追加到 `PSModulePath` 的逻辑
- [x] 5.2 保留 PSModulePath 去重逻辑

## 6. 分阶段计时诊断

- [x] 6.1 在 `profile/profile.ps1` 中用 `[System.Diagnostics.Stopwatch]` 替换 `Get-Date` 计时
- [x] 6.2 在关键阶段（模块加载、代理检测、工具初始化、别名注册）插入计时点
- [x] 6.3 实现 `$script:ProfileTimings` 变量存储各阶段耗时
- [x] 6.4 实现 `POWERSHELL_PROFILE_TIMING=1` 环境变量控制的详细计时输出
- [x] 6.5 默认模式下通过 `Write-Verbose` 输出计时信息

## 7. 验证与测试

- [x] 7.1 在 Windows 上验证 Full 模式加载时间降至 ~1s 以内（需手动验证）
- [x] 7.2 验证 Tab 补全响应速度恢复正常（需手动验证）
- [x] 7.3 验证 starship prompt 正常显示（需手动验证）
- [x] 7.4 验证 Minimal 和 UltraMinimal 模式行为不变（需手动验证）
- [x] 7.5 验证所有别名、函数、环境变量在 Full 模式下仍可用（需手动验证）
- [x] 7.6 运行 `pnpm test:profile` 确保 profile 测试通过
- [x] 7.7 运行 `pnpm qa` 确保整体质量
