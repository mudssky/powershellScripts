# 调整 macOS 安装验证流程

## Goal

调整 `macos/INSTALL.md` 的 macOS 安装步骤说明，并为每个关键步骤提供可脚本化验证的契约，让人和智能体都能按固定命令确认当前机器是否已经完成对应阶段。

## User Value

- 新机器安装时，每一步都有明确的“执行命令”和“验证命令”，失败时能快速定位停在哪一层。
- 智能体可以使用稳定退出码判断安装状态，而不是靠阅读自由文本猜测。
- 安装脚本继续负责写入和部署，验证脚本默认只读，降低误操作风险。

## Confirmed Facts

- `macos/INSTALL.md` 当前按 0-5 步列出 macOS 安装流水线，但每步只有执行方式、前置条件、可跳过和说明，没有机器可读的验证命令。
- `macos/01installHomeBrew.sh` 安装 Homebrew；`macos/02installPowerShell.sh` 通过 Homebrew Cask 安装 PowerShell。
- `macos/03deployShellConfig.sh` 调用 `shell/deploy.sh --shell zsh` 部署根目录 `shell/` 配置片段；旧的 `macos/config/.zshrc` 已归档，不再作为安装目标。
- `macos/04installApps.ps1` 调用 `Install-PackageManagerApps -PackageManager 'homebrew'`，只安装 `supportOs` 包含 `macOS` 且 `tag` 包含 `macbook` 的条目。
- `profile/installer/apps-config.json` 中 `hammerspoon` 已配置 `supportOs: ["macOS"]` 和 `tag: ["macbook"]`，因此第 4 步应能安装 Hammerspoon。
- `macos/05deployHammerspoon.sh` 透传参数给 `macos/hammerspoon/load_scripts.zsh`，后者支持 `--dry-run`、`--no-launch`、`--install`，并把配置部署到 `~/.hammerspoon/`。
- `docs/INSTALL.md` 是跨平台后续安装入口；`macos/INSTALL.md` 最后一行已经引导到该文档。
- 当前工作区已有另一组 Hammerspoon 优化改动处于未提交状态；本任务应避免无关回滚或覆盖。

## Requirements

- 更新 `macos/INSTALL.md`，让每个步骤包含：
  - 前置检查命令。
  - 执行命令。
  - 完成验证命令。
  - 失败后下一步建议或关联脚本。
- 新增一个 macOS 安装验证入口，路径为 `macos/06verifyInstall.zsh`。
- 验证入口应支持：
  - 默认验证全部步骤。
  - 按单步验证，例如 `--step brew`、`--step pwsh`、`--step shell`、`--step apps`、`--step hammerspoon`。
  - 稳定退出码：全部通过返回 0，任一必需项失败返回非 0。
  - 人类可读输出：清楚标出 PASS、WARN、FAIL。
- 验证脚本默认只读，不自动安装、不覆盖配置、不启动 GUI App。
- Hammerspoon 验证应检查部署结果，而不要求验证快捷键实际被触发：
  - Hammerspoon 已安装。
  - `~/.hammerspoon/init.lua`、`config.lua`、`scripts/win.lua` 等托管文件存在。
  - `.powershellscripts-hammerspoon.manifest` 存在且包含托管项。
- Shell 验证应确认 `~/.zshrc` 保留 modular loader，并确认 `~/.bashrc.d` 中存在预期片段链接。
- App 验证首版应验证关键代表项，不必把 `apps-config.json` 中所有 `macbook` 应用都作为强制门槛；完整应用清单检查可作为后续增强。
- 文档需要说明验证脚本不能替代 macOS 权限授权，例如 Hammerspoon 的辅助功能权限仍需用户在系统设置里授权。

## Acceptance Criteria

- [ ] `macos/INSTALL.md` 每个安装阶段都能看到对应验证命令。
- [ ] 新增验证脚本可通过 `zsh macos/06verifyInstall.zsh` 检查完整 macOS 安装状态。
- [ ] 验证脚本可通过 `--step` 只检查单个阶段。
- [ ] 验证脚本在缺少关键依赖时返回非 0，并输出可定位的失败项。
- [ ] 验证脚本默认不写入用户目录、不执行安装、不启动或重启 Hammerspoon。
- [ ] 文档和脚本保持一致，命令路径以仓库根目录执行为默认口径。
- [ ] Shell 语法检查通过：`zsh -n macos/06verifyInstall.zsh`。
- [ ] 文档完整性检查通过：`git diff --check`。
- [ ] 若修改脚本逻辑，执行根目录 `pnpm qa`；若环境阻塞，记录阻塞原因和替代验证。

## Out of Scope

- 不重构现有 `01` 到 `05` 安装脚本的安装行为，除非验证需求暴露出明显文档不一致。
- 不在验证脚本里请求 sudo、安装 Homebrew、安装应用、修改 `~/.zshrc` 或修改 `~/.hammerspoon`。
- 不验证 Hammerspoon 快捷键实际响应，因为这依赖前台 App、辅助功能权限和用户交互。
- 不把跨平台 `docs/INSTALL.md` 的第二阶段实现纳入本任务，只保留交接说明。

## Decisions

- 验证脚本独立放在 `macos/06verifyInstall.zsh`，不扩展到现有 `01` 到 `05` 安装脚本里。
- 首版验证脚本保持只读，不提供 `--fix`，发现问题后由文档提示用户或智能体运行对应安装脚本。
