# macOS 安装指南

本文档描述 macOS 平台的完整安装流水线。按步骤顺序执行即可完成基础环境搭建。

> 此文档需与目录下的脚本保持同步。

## 0. 拉取仓库

- **脚本**: 无（手动执行以下命令）
- **执行方式**: 手动
- **前置条件**: git、网络连接
- **可跳过**: 是（如仓库已存在）
- **说明**: macOS 通常已有 git（Xcode Command Line Tools），直接 clone 即可

```zsh
mkdir -p ~/projects/env && cd ~/projects/env
git clone https://github.com/mudssky/powershellScripts.git
cd powershellScripts/macos
```

## 1. 安装 Homebrew

- **脚本**: `01installHomeBrew.sh`
- **执行方式**: `zsh macos/01installHomeBrew.sh`
- **前置条件**: 网络连接、curl
- **可跳过**: 是（如已安装 Homebrew）
- **说明**: 安装 Homebrew

## 2. 安装 PowerShell

- **脚本**: `02installPowerShell.sh`
- **执行方式**: `zsh macos/02installPowerShell.sh`
- **前置条件**: 步骤 1 完成（需要 Homebrew）
- **可跳过**: 是（如已安装 PowerShell）
- **说明**: 通过 `brew install --cask powershell` 安装 PowerShell

## 3. 部署 Shell 配置

- **脚本**: `03deployShellConfig.sh`
- **执行方式**: `zsh macos/03deployShellConfig.sh`
- **前置条件**: 仓库已 clone（需要 `shell/deploy.sh` 和 `macos/config/.zshrc`）
- **可跳过**: 是
- **说明**: 调用 `shell/deploy.sh` 部署 shell 配置片段，并将 `macos/config/.zshrc` symlink 到 `~/.zshrc`

## 4. 安装应用程序

- **脚本**: `04installApps.ps1`
- **执行方式**: `pwsh macos/04installApps.ps1`
- **前置条件**: 步骤 2 完成（需要 PowerShell）
- **可跳过**: 是
- **说明**: 通过 Homebrew 安装开发工具

## 5. 部署 Hammerspoon 配置

- **脚本**: `05deployHammerspoon.sh`
- **执行方式**: `zsh macos/05deployHammerspoon.sh`
- **前置条件**: Hammerspoon 已安装（可在步骤 4 中安装）
- **可跳过**: 是
- **说明**: 调用 `hammerspoon/load_scripts.zsh` 部署 Hammerspoon 配置到 `~/.hammerspoon/`

---

PowerShell 已就绪，继续执行跨平台安装：[docs/INSTALL.md](../docs/INSTALL.md)
