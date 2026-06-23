# macOS 安装指南

本文档描述 macOS 平台的完整安装流水线。按步骤顺序执行即可完成基础环境搭建，并可用验证脚本确认每个阶段的状态。

> 此文档需与目录下的脚本保持同步。
> 除第 0 步外，以下命令默认在仓库根目录执行。

## 验证入口

- **脚本**: `06verifyInstall.zsh`
- **执行方式**: `zsh macos/06verifyInstall.zsh`
- **说明**: 只读验证当前机器状态，不执行安装、不写入用户目录、不启动或重启 GUI 应用；包含 Hammerspoon、Mos 登录项和 Finder 右键动作验证。
- **退出码**: 全部必需项通过返回 0，任一必需项失败返回非 0；WARN 只提示不影响退出码。

## 0. 拉取仓库

- **脚本**: 无（手动执行以下命令）
- **执行方式**: 手动
- **前置条件**: git、网络连接
- **可跳过**: 是（如仓库已存在）
- **说明**: macOS 通常已有 git（Xcode Command Line Tools），直接 clone 即可

```zsh
mkdir -p ~/projects/env && cd ~/projects/env
git clone https://github.com/mudssky/powershellScripts.git
cd powershellScripts
```

- **验证方式**:

```zsh
zsh macos/06verifyInstall.zsh --step repo
```

## 1. 安装 Homebrew

- **脚本**: `01installHomeBrew.sh`
- **执行方式**: `zsh macos/01installHomeBrew.sh`
- **前置条件**: 网络连接、curl
- **可跳过**: 是（如已安装 Homebrew）
- **说明**: 安装 Homebrew
- **前置检查**:

```zsh
command -v curl
```

- **执行方式**:

```zsh
zsh macos/01installHomeBrew.sh
```

- **验证方式**:

```zsh
zsh macos/06verifyInstall.zsh --step brew
```

- **失败处理**: 如果验证失败，重新执行本步骤；若 Homebrew 官方安装脚本下载失败，先检查网络或代理。

## 2. 安装 PowerShell

- **脚本**: `02installPowerShell.sh`
- **执行方式**: `zsh macos/02installPowerShell.sh`
- **前置条件**: 步骤 1 完成（需要 Homebrew）
- **可跳过**: 是（如已安装 PowerShell）
- **说明**: 通过 `brew install --cask powershell` 安装 PowerShell
- **前置检查**:

```zsh
zsh macos/06verifyInstall.zsh --step brew
```

- **执行方式**:

```zsh
zsh macos/02installPowerShell.sh
```

- **验证方式**:

```zsh
zsh macos/06verifyInstall.zsh --step pwsh
```

- **失败处理**: 如果验证失败，确认 Homebrew 可用后重新执行本步骤。

## 3. 部署 Shell 配置

- **脚本**: `03deployShellConfig.sh`
- **执行方式**: `zsh macos/03deployShellConfig.sh`
- **前置条件**: 仓库已 clone（需要 `shell/deploy.sh`、`shell/shared.d/` 和 `shell/zsh.d/`）
- **可跳过**: 是
- **说明**: 调用 `shell/deploy.sh` 部署根目录 `shell/` 下的配置片段，并确保 `~/.zshrc` 加载 `~/.bashrc.d/`；不会替换整个 `~/.zshrc`。
- **前置检查**:

```zsh
zsh macos/06verifyInstall.zsh --step repo
```

- **执行方式**:

```zsh
zsh macos/03deployShellConfig.sh
```

- **验证方式**:

```zsh
zsh macos/06verifyInstall.zsh --step shell
```

- **失败处理**: 如果验证失败，检查 `~/.zshrc` 是否保留 modular loader，必要时重新执行本步骤。

## 4. 安装应用程序

- **脚本**: `04installApps.ps1`
- **执行方式**: `pwsh macos/04installApps.ps1`
- **前置条件**: 步骤 2 完成（需要 PowerShell）
- **可跳过**: 是
- **说明**: 通过 Homebrew 安装带有 `macOS` 支持且包含 `macbook` 标签的开发工具和 macOS 应用。
- **前置检查**:

```zsh
zsh macos/06verifyInstall.zsh --step brew
zsh macos/06verifyInstall.zsh --step pwsh
```

- **执行方式**:

```zsh
pwsh macos/04installApps.ps1
```

- **验证方式**:

```zsh
zsh macos/06verifyInstall.zsh --step apps
```

- **失败处理**: 如果验证失败，确认 `profile/installer/apps-config.json` 中目标应用未被 `skipInstall` 跳过，再重新执行本步骤。

## 5. 部署 Hammerspoon 配置

- **脚本**: `05deployHammerspoon.sh`
- **执行方式**: `zsh macos/05deployHammerspoon.sh`
- **前置条件**: Hammerspoon 已安装（可在步骤 4 中安装）
- **可跳过**: 是
- **说明**: 调用 `hammerspoon/load_scripts.zsh` 部署 Hammerspoon 配置到 `~/.hammerspoon/`
- **前置检查**:

```zsh
zsh macos/06verifyInstall.zsh --step apps
```

- **执行方式**:

```zsh
zsh macos/05deployHammerspoon.sh
```

- **验证方式**:

```zsh
zsh macos/06verifyInstall.zsh --step hammerspoon
```

- **失败处理**: 如果验证失败，先确认 Hammerspoon 已安装；未安装时执行 `pwsh macos/04installApps.ps1` 或 `zsh macos/05deployHammerspoon.sh --install`。
- **权限说明**: 验证脚本只检查文件部署状态，不检查快捷键是否可触发。首次使用 Hammerspoon 时仍需在 macOS 系统设置中授予辅助功能权限。

## 6. 配置登录启动项

- **脚本**: `07configureLoginItems.zsh`
- **执行方式**: `zsh macos/07configureLoginItems.zsh`
- **前置条件**: Hammerspoon 和 Mos 已安装
- **可跳过**: 是
- **说明**: 将 Hammerspoon 和 Mos 加入当前用户登录项，确保合盖守卫和鼠标滚动优化在重新登录后自动恢复。
- **前置检查**:

```zsh
zsh macos/06verifyInstall.zsh --step apps
```

- **执行方式**:

```zsh
zsh macos/07configureLoginItems.zsh
```

- **验证方式**:

```zsh
zsh macos/06verifyInstall.zsh --step login-items
```

- **失败处理**: 如果脚本提示无法读取或写入登录项，按系统弹窗授予终端对 System Events 的自动化权限后重新执行。

## 7. 安装 Finder 右键动作

- **脚本**: `08installQuickActions.zsh`
- **执行方式**: `zsh macos/08installQuickActions.zsh`
- **前置条件**: 仓库已 clone，Finder 可用
- **可跳过**: 是
- **说明**: 将仓库维护的 Automator workflow 安装到 `~/Library/Services/`，用于在 Finder 右键快捷操作中处理下载后的 `.app` 打不开问题。workflow 只作为 Finder 入口，实际动作由 `macos/quick-actions/run.zsh` 按动作 ID 分派。
- **前置检查**:

```zsh
zsh macos/06verifyInstall.zsh --step repo
```

- **执行方式**:

```zsh
zsh macos/08installQuickActions.zsh
```

- **验证方式**:

```zsh
zsh macos/06verifyInstall.zsh --step quick-actions
```

- **使用方式**: 在 Finder 中选中一个或多个 `.app`，右键选择“快捷操作”或“服务”中的“处理 macOS 应用打不开”。脚本会打开 Terminal，依次输出 Gatekeeper 检查、签名检查、隔离属性检查，随后清除 `com.apple.quarantine` 并尝试打开应用。
- **安全说明**: 该动作会自动清除传入 `.app` 的 quarantine 属性，只应对可信来源应用使用；它不会全局关闭 Gatekeeper，也不会处理非 `.app` 文件。
- **失败处理**: 如果右键菜单未立即显示，重新打开 Finder 窗口或重启 Finder；首次执行若系统弹出自动化权限提示，允许 Finder/Automator 控制 Terminal 后重试；如果验证失败，重新执行安装脚本。
- **卸载方式**:

```zsh
zsh macos/08installQuickActions.zsh --uninstall
```

## 8. 总体验证

- **脚本**: `06verifyInstall.zsh`
- **执行方式**:

```zsh
zsh macos/06verifyInstall.zsh
```

- **说明**: 检查仓库结构、Homebrew、PowerShell、Shell 配置、关键 macOS 应用、Hammerspoon 配置部署结果、登录启动项和 Finder 右键动作。

---

PowerShell 已就绪，继续执行跨平台安装：[docs/INSTALL.md](../docs/INSTALL.md)
