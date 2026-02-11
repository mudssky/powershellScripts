## 1. 环境变量检测 API 替换

- [ ] 1.1 将 `profile/core/mode.ps1` 中 `Test-EnvSwitchEnabled` 函数的 `Get-Item -Path "Env:$Name"` 替换为 `[System.Environment]::GetEnvironmentVariable($Name)`，保持返回值语义不变
- [ ] 1.2 将 `profile/core/mode.ps1` 中 `Test-EnvValuePresent` 函数的 `Get-Item -Path "Env:$Name"` 替换为 `[System.Environment]::GetEnvironmentVariable($Name)`，保持返回值语义不变
- [ ] 1.3 验证 `Get-ProfileModeDecision` 在各种环境变量组合下的行为与替换前一致（Full / Minimal / UltraMinimal / Codex 自动降级 / 默认）

## 2. psutils 分层延迟加载

- [ ] 2.1 改造 `profile/core/loadModule.ps1`：移除 `Import-Module psutils.psd1`，改为按依赖顺序 dot-source 6 个核心子模块（`os` → `cache` → `test` → `env` → `proxy` → `wrapper`）
- [ ] 2.2 在 `loadModule.ps1` 中将 psutils 模块父目录追加到 `$env:PSModulePath`（去重检查），作为自动加载兜底
- [ ] 2.3 在 `loadModule.ps1` 中注册 `Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action { Import-Module psutils.psd1 -Force -Global }`，实现空闲时全量加载
- [ ] 2.4 为 OnIdle 事件的 Action 添加 `try/catch` 错误处理，失败时通过 `Write-Warning` 静默记录
- [ ] 2.5 保留 `loadModule.ps1` 中的 PSModulePath 去重逻辑（现有的 `HashSet` 去重代码）

## 3. wrapper.ps1 延迟加载

- [ ] 3.1 将 `profile/core/loaders.ps1` 中 `wrapper.ps1` 的 dot-source 从同步阶段移到 OnIdle 事件中（与 psutils 全量加载合并在同一个 OnIdle Action 中）
- [ ] 3.2 确认 `Set-AliasProfile` 所依赖的 `Set-CustomAlias` / `Get-CustomAlias` 来自 `wrapper.psm1`（核心子模块同步阶段已加载），不依赖 `wrapper.ps1`

## 4. fnm 初始化缓存化

- [ ] 4.1 将 `profile/features/environment.ps1` 中 fnm 初始化从 `fnm env --use-on-cd | Out-String | Invoke-Expression` 改为 `Invoke-WithFileCache -Key "fnm-init-powershell" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { fnm env --use-on-cd } -BaseDir (Join-Path $profileRoot '.cache')` + dot-source 缓存文件
- [ ] 4.2 验证 fnm 缓存文件内容可被正确 dot-source（环境变量设置和 `use-on-cd` hook 正常工作）

## 5. 验证与回归测试

- [ ] 5.1 使用 `POWERSHELL_PROFILE_TIMING=1` 运行 profile，验证 `core-loaders` 阶段从 ~680ms 降至 ~230ms
- [ ] 5.2 验证 Full 模式下总加载时间降至 ~1.1s 以下
- [ ] 5.3 验证 prompt 显示后执行 `Get-Tree`（非核心函数）可正常工作（PSModulePath 自动加载兜底）
- [ ] 5.4 验证 OnIdle 触发后所有 70+ 个 psutils 函数可 Tab 补全
- [ ] 5.5 验证 UltraMinimal 模式行为不变（跳过所有模块加载）
- [ ] 5.6 验证 Minimal 模式行为不变（加载模块但跳过工具和别名）
- [ ] 5.7 运行 `pnpm test:fast` 确保现有 Pester 测试全部通过
