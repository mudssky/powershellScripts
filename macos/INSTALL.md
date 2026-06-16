# macOS 安装指南

本文档描述 macOS 平台的完整安装流水线。按步骤顺序执行即可完成基础环境搭建，并可用验证脚本确认每个阶段的状态。

> 此文档需与目录下的脚本保持同步。
> 除第 0 步外，以下命令默认在仓库根目录执行。

## 验证入口

- **脚本**: `06verifyInstall.zsh`
- **执行方式**: `zsh macos/06verifyInstall.zsh`
- **说明**: 只读验证当前机器状态，不执行安装、不写入用户目录、不启动或重启 GUI 应用。
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

## 6. 总体验证

- **脚本**: `06verifyInstall.zsh`
- **执行方式**:

```zsh
zsh macos/06verifyInstall.zsh
```

- **说明**: 检查仓库结构、Homebrew、PowerShell、Shell 配置、关键 macOS 应用和 Hammerspoon 配置部署结果。

---

PowerShell 已就绪，继续执行跨平台安装：[docs/INSTALL.md](../docs/INSTALL.md)
