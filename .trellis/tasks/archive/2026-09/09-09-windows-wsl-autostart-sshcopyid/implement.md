# Implement：执行清单

## 顺序步骤

1. `config/install/steps.psd1`：windows `10 login-items` 条目激活（`Supported = $true`、`Path = 'windows/10deployWslAutostart.ps1'`、`Runner = 'pwsh'`、`PreviewArgument = '-WhatIf'`），确认 Core/Full Presets 与相邻条目一致。
2. 新建 `windows/10deployWslAutostart.ps1`：薄封装 `Initialize-WslSshAccess.ps1`（参数默认值推断、前置检查 → Blocked/10、`-WhatIf` 透传、结果转译为叶子文本输出 + 退出码约定）；帮助文档按仓库 .SYNOPSIS/.PARAMETER 风格。
3. `profile/installer/apps-config.json`：winget 段新增 SSHCopyID 条目（对照 autohotkey/eartrumpet 的字段结构）。
4. `windows/99verifyInstall.ps1` + `windows/pwsh/Test-InstallState.ps1`：按现有检查模式新增 login-items/SSHCopyID 检查（只读）。
5. `windows/INSTALL.md`：手动入口段落标注"或由流水线步骤 10 自动完成"。
6. Pester：`tests/WindowsInstallPipeline.Tests.ps1` 增补（steps 注册、叶子 WhatIf、Blocked 路径、apps-config 条目校验）；`tests/WslSshAccess.Tests.ps1` 如受参数变化影响同步。

## 验证命令

```bash
pnpm qa                                   # changed 范围（含 Pester fast）
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode fast -Path ./tests/WindowsInstallPipeline.Tests.ps1
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode fast -Path ./tests/WslSshAccess.Tests.ps1
pnpm test:pwsh:all                        # 主会话统一跑（双 lane）
```

## 风险文件与回滚

- `config/install/steps.psd1`：windows 10 条目回退为 `Supported = $false` 即摘除步骤。
- `profile/installer/apps-config.json`：SSHCopyID 条目独立可删。
- `windows/10deployWslAutostart.ps1`：新文件，独立可删。
- 机制层 `windows/wsl/WslSshAccess.psm1` 原则上零改动；如确需最小改动，须保持 `tests/WslSshAccess.Tests.ps1` 全绿并在报告中单列。

## task.py start 前检查

- [x] prd.md 收敛（无未决 Open Questions）
- [x] design.md / implement.md 就绪
- [ ] implement.jsonl / check.jsonl 各含至少 1 条真实条目（add-context）
- [ ] 用户明确批准最终规划摘要
