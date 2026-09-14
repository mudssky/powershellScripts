# Windows 开机自启 WSL 与 SSHCopyID 安装

## Goal

让 Windows 宿主在自动更新重启后（即使停在登录界面）自动恢复 `Windows:2222 → WSL sshd` 的远程开发链路，并补齐 Windows 侧 `ssh-copy-id` 体验。目标链路：远程设备 → Tailscale → Windows:2222 → WSL Ubuntu sshd → 开发环境。

## Background（2026-09-09 勘察结论）

链路本体已存在，缺的只是"接入流水线"与"SSHCopyID 清单条目"：

- **WSL SSH 链路已实现**：`windows/wsl/Initialize-WslSshAccess.ps1` —— Windows portproxy 监听 **2222** → WSL sshd **2223**（避开 Win32 OpenSSH 22）；`Invoke-WslSshAccessRefresh.ps1` 启动 WSL sshd 并运行长驻 TCP relay（keepalive）。
- **开机自启计划任务已实现**：`windows/wsl/WslSshAccess.psm1:476-480` —— `AtStartup` 触发 + `LogonType S4U`（不依赖交互登录）+ `RunLevel Highest` + `StartWhenAvailable` + 失败重启 3 次/1 分钟。
- **网络底座已就位**：`.wslconfig` 模板为 `networkingMode=mirrored` + `hostAddressLoopback=true`（windows/wsl/README.md，最低 build 22621）。
- **缺口 1**：链路是独立手动入口（windows/INSTALL.md:143-167），未接入流水线；`config/install/steps.psd1` 中 windows 10 login-items 为 `Supported = $false`。
- **缺口 2**：`profile/installer/apps-config.json` 无 SSHCopyID（winget 段仅 autohotkey、eartrumpet）。
- Tailscale on Windows 为既有前提（bootstrap 前提条件），不在本任务安装范围。

## Requirements

1. **激活 windows 步骤 10 login-items**：`config/install/steps.psd1` 中 windows 条目改为 `Supported = $true`，指向新叶子 `windows/10deployWslAutostart.ps1`（Core 与 Full 均包含，与既有步骤 Presets 一致）。
2. **新叶子 `windows/10deployWslAutostart.ps1`**：薄封装 `windows/wsl/Initialize-WslSshAccess.ps1`，行为约定：
   - 幂等（重复执行收敛到既定状态，复用 Initialize 现有 verify/plan 能力）；
   - 前置不足（无 WSL 发行版 / 非 build 22621+ / 用户参数无法解析）时返回 `Blocked`（exit 10），遵循仓库退出码约定，不静默回退；
   - 参数提供合理默认（DistroName 缺省时从 `wsl -l -q` 解析默认发行版，WindowsUser 取当前用户），允许显式覆盖；
   - 支持 `-WhatIf` 预览与 `--dry-run` 语义对齐（PreviewArgument = `-WhatIf`）。
3. **SSHCopyID 清单条目与安装接线**：`profile/installer/apps-config.json` winget 段新增 `axeprpr.SSHCopyID`（`winget install --id axeprpr.SSHCopyID -e --accept-package-agreements --accept-source-agreements`，supportOs 含 Windows），通过 `Test-PackageManagerAppCatalog` 校验；包为 portable 安装（per-user 免 UAC），由 08 Full 用户阶段新增的 winget catalog 消费方自动安装。
4. **验证接线**：`windows/99verifyInstall.ps1` 覆盖新步骤的可检项（计划任务存在且 Trigger/Principal 匹配、portproxy 监听、SSHCopyID 已安装——复用 `windows/wsl/WslSshAccess.psm1` 既有 verify 能力与 psutils 应用检测）。
5. **文档**：`windows/INSTALL.md` 手动入口段落改为推荐流水线路径，保留手动命令作为等价入口。

## Acceptance Criteria

- [x] `steps.psd1` windows 10 login-items 指向新叶子且 `pnpm provision:list` / `install.ps1 -ListSteps` 正确显示（实现与 Pester 步骤注册表断言验证）。
- [x] 新叶子在 `-WhatIf` 下输出计划且零落盘；WSL 缺席场景返回 Blocked/10（Pester 35/35 + 容器冒烟；含"Blocked 优先于参数错误"静态顺序守卫）。
- [x] `apps-config.json` 通过 `Test-PackageManagerAppCatalog`；SSHCopyID（tag full/platform）由 08 Full 新增的 winget catalog 消费方自动安装（portable 免 UAC，Pester 39 用例含命令构造与 skipInstall 排除断言）。
- [x] `windows/99verifyInstall.ps1` 包含 login-items 检查项且单文档 JSON 契约不破坏（Pester 断言）。
- [x] `pnpm test:pwsh:all` 双 lane 全绿（host 952/0，linux 950/0，exit 0）；真实 Windows 宿主的端到端行为验收由用户实机执行（人工验收项）。

## Decisions（check 裁决记录）

- login-items Presets 保持 `@('Full')`（对齐 09/11 相邻步骤与 DependsOn full-apps 的 Full-only 语义），PRD 初稿"Core 与 Full 均包含"按 check 裁决视为例外。
- 99 的 login-items 检查不复用机制层 `Invoke-WslSshAccess -Operation Verify`（其需公钥且会在 WSL 内跑 bash，违反 99 只读契约），改为 `WindowsInstall.psm1` 只读 `Get-WindowsWslSshLoginItemsState` 复用机制层命名与 Trigger/Principal 谓词。
- winget 消费方缺口已闭合：实机 `winget show` 确认 axeprpr.SSHCopyID 安装程序类型为 portable（per-user、免 UAC），符合 08 非提升用户阶段约束。已新增 `Invoke-WindowsWingetCatalogInstall`（镜像 scoop 包装，WindowsInstall.psm1）并在 `08installFullApps.ps1` 接线（tag full/platform，Full 预设自动安装 SSHCopyID；eartrumpet skipInstall 排除；autohotkey 经 AlreadyPresent 与 09 路径去重）。check 确认与 scoop 包装同构、flags 透传属实、39 用例全绿。

## Out of Scope

- RustDesk on Windows（单独任务；装本体之外还需中继/Key/自启服务配置才有救援价值）。
- Tailscale on Windows 的安装与登录（既有前提）。
- WSL/Ubuntu 发行版发行与 systemd 启用本身（`linux/wsl/wsl.conf`、prepare-ssh-access.sh 既有链路）。
- 真实 Windows 宿主上的端到端连线测试（CI 无 Windows 宿主）。

## Open Questions

无。
