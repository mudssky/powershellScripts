# Windows 安装流水线实施计划

## 开始门禁

- [x] 用户审阅 `prd.md`、`design.md` 与本计划，并明确批准实现。
- [x] 执行 `task.py start 07-10-windows-install-pipeline`，确认状态为 `in_progress`。
- [x] 加载 `trellis-before-dev`，阅读 infra、pwsh-scripts、profile、psutils 与现有 macOS/Linux 安装规范。
- [x] 记录 `git status --short`，只处理 Windows 子任务；不吸收 Nix、归档或父任务目录。

## 1. 平台模型与声明式配置

- [x] 新增 `config/install/windows-packages.psd1`，声明 Stage 0 package ID、Scoop bucket、字体和 WSL 默认值。
- [x] 新增 `windows/pwsh/WindowsInstall.psm1`，实现 edition/build/architecture/Server/admin/winget/pwsh/Scoop/WSL capability 模型。
- [x] 提供 registry/build/architecture/command 覆盖注入，仅用于 fixture 测试。
- [x] 实现统一组件结果和 Failed > Blocked/RestartRequired > success 退出优先级。
- [x] 覆盖 Windows 11、Windows 10、ARM64、Server/CI、非 Windows 与提升状态矩阵。

## 2. Stage 0 bootstrap 与一次 UAC

- [x] 新增 PS5.1-compatible `windows/bootstrap/WindowsBootstrap.psm1`，收口 TLS、下载、签名校验、PATH 刷新和 bootstrap 结果。
- [x] 新增 `windows/bootstrap/bootstrap-manifest.psd1`，声明 clone 前所需最小资产相对路径与 SHA256；远程 00 必须逐项下载校验。
- [x] 新增 `Invoke-WindowsElevatedPlan.ps1`，只接受 WingetInstall/MsiInstall/ExeInstaller/WslInstall allowlist operation。
- [x] 重写/新增 `windows/00quickstart.ps1`，支持 repo/preset/network、Git/PowerShell/AutoHotkey 本地 installer、interaction/IncludeWsl/WhatIf。
- [x] 在提升前预检 Git/pwsh、Full/AHK 与 IncludeWsl，把缺失机器组件合并为一次 operation plan；UAC 取消、NonInteractive、reboot 和失败映射稳定退出码。
- [x] winget 优先精确安装 Git.Git 与 Microsoft.PowerShell；Direct 无 winget时使用官方签名 installer/MSI。
- [x] 远程 bootstrap 下载 manifest、模块、提升 helper、winget source helper 与两份声明配置，clone 使用 `--depth=1`；已有 clone 不 pull、不改 history。
- [x] 使用 fake/fixture 与 WhatIf 验证单次提升计划、执行顺序、manifest hash、PATH 合并和零写入；真实 UAC 留给 Windows smoke。

## 3. Scoop 与 PowerShell 叶子

- [x] 新增 `windows/01installScoop.ps1`，普通用户安装/验证 Scoop，拒绝管理员上下文。
- [x] 新增 `windows/02installPowerShell.ps1`，复用 bootstrap 模块并支持本地 MSI、winget、版本验证与 WhatIf。
- [x] China/Auto 缺可恢复 adapter或本地 installer 时返回 10，不隐藏 Direct fallback。
- [x] 01/02 独立执行与 00 组合执行保持同一结构化状态和退出码。

## 4. Sources 与应用清单分层

- [x] 新增 `windows/pwsh/Invoke-WindowsSources.ps1` 与 `windows/03configureSources.ps1`，组合 winget 只读 capability/snapshot 与 npm/pnpm/pip/go；不得把 winget 伪装成 Stage 1 transaction target。
- [x] 保证 Direct/China/Auto、共享 transaction ID、Stage 0 winget snapshot/Restore 状态和单文档 JSON 合同。
- [x] 为 Scoop 10 个 Core CLI 增加 `core + cli` 与 Windows support 标签。
- [x] 为确认的跨平台扩展增加 `terminal-extras + cli` 与 Windows support 标签，其余 Scoop 项保持未分类。
- [x] 新增 AutoHotkey winget `full + platform` 条目；EarTrumpet/Twinkle Tray/Neovide 保持显式可选或 skip。
- [x] 校验 Scoop/winget/Chocolatey 没有默认重复所有权。

## 5. Core CLI 与字体

- [x] 新增 `windows/05installCoreCli.ps1`，只选择 Scoop `Windows + core + cli`。
- [x] 新增 `windows/06installFonts.ps1`，幂等管理 nerd-fonts bucket、JetBrainsMono-NF 与 FiraCode-NF。
- [x] 两个叶子支持 WhatIf、逐项结果、缺 Scoop Blocked 和 Server/ARM 限制。
- [x] 将 `profile/installer/installFont.ps1` 收敛为兼容包装，不保留第二份 Windows 字体列表。
- [x] 覆盖 Core 精确集合、skipInstall、部分失败继续、bucket 已存在、字体已安装与无真实字体写入。

## 6. Profile Tools 与 PATH

- [x] 扩展 `ProfileTools.psm1` 支持 Windows，复用模块、Profile、fnm、pnpm、bin、Node build 与 nbstripout。
- [x] Windows 分支不运行 Bash build，不复制 macOS/Linux 主体。
- [x] 新增 `windows/07installProfileTools.ps1`，追加根目录/bin User PATH 幂等写入与当前进程刷新。
- [x] 检测提升后的 Stage 1 并在用户配置前返回 Blocked/10。
- [x] 运行 macOS/Linux 现有流水线测试，锁定共享模块无回归。

## 7. Full 与 AutoHotkey

- [x] 新增 `windows/08installFullApps.ps1`，只选择 Scoop `Windows + cli + terminal-extras`。
- [x] 重构 `scripts/ahk/install-autohotkey.ps1`，移除 ReadKey/隐式提示并提供结构化/WhatIf 入口或兼容包装。
- [x] 重构 `scripts/ahk/makeScripts.ps1`，支持 ShouldProcess、临时 Output/Startup、NoAutoStart 和可测试 shortcut runner。
- [x] 新增 `windows/09deployAutoHotkey.ps1`，验证 AHK v2并部署当前用户 Startup；经 00 进入时不得再次提升，独立执行缺失时最多构造一次提升。
- [x] 覆盖 Stage 0 已安装、独立安装预览、二次 UAC 拒绝、组合脚本幂等、快捷方式已存在和测试零进程启动。

## 8. WSL 宿主

- [x] 将 `linux/wsl2/.wslconfig` 与 `loadWslConfig.ps1` 迁到 `windows/wsl/`，更新有效引用。
- [x] 新增 `Initialize-WslHost.ps1`，仅显式 IncludeWsl 生成 install/no-launch 需求并执行用户配置/发行版移交；机器 operation 由 00 合并，根编排器参数保持不变。
- [x] `.wslconfig` 内容变化时备份、临时文件验证和原子替换，返回 RestartRequired/10。
- [x] 在 `windows-packages.psd1` 为有版本要求的 WSL 配置键声明 minimum build/capability；Windows 10 只生成满足条件的配置，Windows 11 22H2+ 保留完整模板。
- [x] 不执行 shutdown/terminate/unregister；输出手工 shutdown 与 Linux guest bootstrap handoff。
- [x] 覆盖未 opt-in、WSL 缺失、单次提升边界、配置相同/变化、Windows 10 capability 和 WhatIf 零写入。

## 9. 只读验证与兼容

- [x] 新增 `windows/pwsh/Test-InstallState.ps1` 与 `windows/99verifyInstall.ps1`，支持 Core/Full、Step、IncludeWsl、Text/Json。
- [x] 从 apps/windows package catalog 读取 CLI、字体、AHK 和 WSL 期望，不维护第二份名称。
- [x] 默认 WSL 缺失为 Skipped；精确 WSL 验证才计 Blocked/Fail。
- [x] JSON stdout 单文档，ARM/Server/重启状态不伪装成功。
- [x] 保留 `install.ps1 -installApp` 弃用全量兼容入口，并更新 Windows 新入口引用。

## 10. 文档与 QA 发现性

- [x] 新增 `windows/INSTALL.md`，说明 Stage 0、Core/Full、一次 UAC、PATH、AHK、WSL opt-in 和手工 smoke。
- [x] 更新 `docs/INSTALL.md`、`docs/scripts-index.md`、WSL/换源说明与 Windows 安装合同。
- [x] 新增 `.trellis/spec/infra/windows-install-pipeline.md` 并更新 infra index/相关跨平台规范。
- [x] 新增 `tests/WindowsInstallPipeline.Tests.ps1`，接入 Pester QA 默认集合与 `scripts/qa.mjs` Windows 路由。
- [x] Windows test workflow 会在 `windows-latest` 发现全量 Pester；当前本机已验证 macOS 与 Linux Docker，真实 Windows run 待推送后确认。

## 11. 质量门禁

- [x] PowerShell parser、PSD1/JSON 加载和 `git diff --check` 通过。
- [x] Windows Pipeline Pester 在当前 host unit/fixture 通过。
- [x] `pnpm qa` 通过。
- [x] `pnpm test:pwsh:all` 通过，macOS host 与 Linux Docker 无回归。
- [ ] GitHub Actions `windows-latest` 通过新增 Windows 全量 WhatIf/fixture 断言（待推送后确认）。
- [x] 测试未执行真实 winget/Scoop/MSI/UAC/font/Startup/AHK/WSL 写操作。

最终验证：

```bash
pnpm qa
pnpm test:pwsh:all
git diff --check
```

Windows CI：

```powershell
$env:PWSH_TEST_MODE = 'full'
$config = ./PesterConfiguration.ps1
Invoke-Pester -Configuration $config
```

## 12. 收尾

- [x] 使用 `trellis-check` 完成规范、复用、跨层数据流和测试审查。
- [x] 记录真实 Windows 11 Core smoke checklist 为后续运行态验证，不伪造已执行结果。
- [ ] 按实现/测试与文档/规范拆分提交，不提交 Nix、归档或父任务目录。
- [ ] 归档当前任务并记录 journal。

## 风险与回滚点

- Stage 0 是 PS5.1 与远程执行边界，不能使用未验证的 PowerShell 7-only 语法。
- 提升 helper 是高风险面，operation 必须 allowlist，禁止执行配置提供的任意脚本文本。
- `ProfileTools.psm1` 扩展影响 macOS/Linux，先跑现有窄测再继续 Windows 平台组件。
- `profile/installer/apps-config.json` 标签修改影响共享 catalog validator，必须验证 Core/Full 精确集合和重复所有权。
- AHK 与 `.wslconfig` 是用户运行态写入，测试必须使用可覆盖路径和 fake runner。
- Windows CI 只能证明 fixture/WhatIf 合同；真实 UAC、字体、Startup 和 WSL 运行态需要后续手工 smoke。
