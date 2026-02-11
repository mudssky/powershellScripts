## 1. 环境变量检测 API 替换

- [x] 1.1 将 `profile/core/mode.ps1` 中 `Test-EnvSwitchEnabled` 函数的 `Get-Item -Path "Env:$Name"` 替换为 `[System.Environment]::GetEnvironmentVariable($Name)`，保持返回值语义不变
- [x] 1.2 将 `profile/core/mode.ps1` 中 `Test-EnvValuePresent` 函数的 `Get-Item -Path "Env:$Name"` 替换为 `[System.Environment]::GetEnvironmentVariable($Name)`，保持返回值语义不变
- [x] 1.3 验证 `Get-ProfileModeDecision` 在各种环境变量组合下的行为与替换前一致（Full / Minimal / UltraMinimal / Codex 自动降级 / 默认）

## 2. psutils 分层延迟加载

- [x] 2.1 改造 `profile/core/loadModule.ps1`：移除 `Import-Module psutils.psd1`，改为按依赖顺序 Import-Module 6 个核心子模块（`os` → `cache` → `test` → `env` → `proxy` → `wrapper`）
- [x] 2.2 在 `loadModule.ps1` 中将 psutils 模块父目录追加到 `$env:PSModulePath`（去重检查），作为自动加载兜底
- [x] 2.3 在 `loadModule.ps1` 中注册 `Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action { Import-Module psutils.psd1 -Force -Global }`，实现空闲时全量加载
- [x] 2.4 为 OnIdle 事件的 Action 添加 `try/catch` 错误处理，失败时通过 `Write-Warning` 静默记录
- [x] 2.5 保留 `loadModule.ps1` 中的 PSModulePath 去重逻辑（现有的 `HashSet` 去重代码）

## 3. wrapper.ps1 延迟加载

- [x] 3.1 将 `profile/core/loaders.ps1` 中 `wrapper.ps1` 的 dot-source 从同步阶段移到 OnIdle 事件中（与 psutils 全量加载合并在同一个 OnIdle Action 中）
- [x] 3.2 确认 `Set-AliasProfile` 所依赖的 `Set-CustomAlias` / `Get-CustomAlias` 来自 `wrapper.psm1`（核心子模块同步阶段已加载），不依赖 `wrapper.ps1`

## 4. fnm 初始化优化

- [x] 4.1 将 `profile/features/environment.ps1` 中 fnm 初始化从 `fnm env --use-on-cd | Out-String | Invoke-Expression` 改为临时文件 dot-source 方式（fnm env 输出包含会话特定 multishell 临时路径，不适合长期缓存，改用临时文件 dot-source 替代字符串 Invoke-Expression）
- [x] 4.2 验证 fnm env 输出为 PowerShell 语法（在 pwsh 进程中自动输出 `$env:` 语法而非 bash `export`），可正确 dot-source

## 5. 验证与回归测试

- [x] 5.1 使用 `POWERSHELL_PROFILE_TIMING=1` 运行 profile，验证 `core-loaders` 阶段从 ~680ms 降至 ~77ms（超额完成，节省 ~600ms）
- [x] 5.2 验证 `mode-decision` 阶段从 ~88ms 降至 ~47ms（节省 ~41ms）。总加载时间受 `initialize-environment` 外部操作（Sync-PathFromBash、fnm、starship、proxy）制约，冷启动约 1750ms，热缓存约 970ms
- [x] 5.3 验证 prompt 显示后执行 `Get-Tree`（非核心函数）可正常工作（PSModulePath 自动加载兜底），source 显示为 `psutils`
- [ ] 5.4 验证 OnIdle 触发后所有 70+ 个 psutils 函数可 Tab 补全（需在交互式 shell 中手动验证）
- [x] 5.5 验证 UltraMinimal 模式行为不变（跳过所有模块加载）
- [x] 5.6 验证 Minimal 模式行为不变（加载模块但跳过工具和别名）
- [x] 5.7 运行 `pnpm test:fast` 确保现有 Pester 测试全部通过（324 passed, 0 failed）
