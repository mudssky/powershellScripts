## 1. PSReadLine 键绑定延迟注册

- [ ] 1.1 从 `profile/core/encoding.ps1` 的 `Set-ProfileUtf8Encoding` 中移除 `Set-PSReadLineKeyHandler -Key Tab -Function Complete`
- [ ] 1.2 在 `profile/core/loadModule.ps1` 的 OnIdle Action 中添加 `Set-PSReadLineKeyHandler -Key Tab -Function Complete`（在 fzf 键绑定注册之后）

## 2. starship 缓存平台隔离

- [ ] 2.1 在 `profile/features/environment.ps1` 中将 starship init 缓存 key 从 `starship-init-powershell` 改为 `starship-init-powershell-<platform>`（`win`/`linux`/`macos`）
- [ ] 2.2 同步修改 zoxide init 缓存 key 为 `zoxide-init-powershell-<platform>`（保持一致性）

## 3. 缓存 starship continuation prompt

- [ ] 3.1 在 starship init 缓存生成后，添加 post-processing 逻辑：用 `Invoke-WithFileCache` 缓存 `starship prompt --continuation` 的输出
- [ ] 3.2 用正则替换将缓存脚本中的 `Set-PSReadLineOption -ContinuationPrompt (Invoke-Native ...)` 替换为缓存字面量
- [ ] 3.3 实现 fallback：正则替换失败时保留原始 `Invoke-Native` 调用并通过 `Write-Verbose` 记录

## 4. 验证与清理

- [ ] 4.1 在 Windows 和 Linux 上分别运行 `POWERSHELL_PROFILE_TIMING=1` 验证优化效果
- [ ] 4.2 确认 OnIdle 触发后 Tab 补全行为正确（`Complete` 模式）
- [ ] 4.3 删除诊断脚本 `profile/.cache/pf-diag.ps1`
- [ ] 4.4 运行 `pnpm qa` 确保无回归
