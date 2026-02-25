# Linux 安装指南

本文档描述 Linux 平台的完整安装流水线。按步骤顺序执行即可完成基础环境搭建。

> 此文档需与目录下的脚本保持同步。

## 0. 拉取仓库

- **脚本**: `00quickstart.sh`
- **执行方式**: `bash linux/00quickstart.sh`
- **前置条件**: 网络连接、git（脚本会自动安装 gh）
- **可跳过**: 是（如仓库已存在）
- **说明**: 安装 GitHub CLI，登录后 clone 仓库到 `~/projects/env/powershellScripts`

如果不使用 `gh`，也可以手动 clone：

```bash
mkdir -p ~/projects/env && cd ~/projects/env
git clone https://github.com/mudssky/powershellScripts.git
cd powershellScripts/linux
```

## 1. 安装 Homebrew

- **脚本**: `01installHomeBrew.sh`
- **执行方式**: `bash linux/01installHomeBrew.sh`
- **前置条件**: 网络连接、curl、git
- **可跳过**: 是（如已安装 Homebrew）
- **说明**: 安装 Homebrew 并配置环境变量。优先使用官方源，网络不通时自动切换清华源

## 2. 安装 PowerShell

- **脚本**: `02installPowerShell.sh`
- **执行方式**: `bash linux/02installPowerShell.sh`
- **前置条件**: 步骤 1 完成（需要 dpkg/apt 或 Homebrew）
- **可跳过**: 是（如已安装 PowerShell）
- **说明**: 优先使用本地 deb 文件安装，失败则回退到 installer 脚本

## 3. 部署 Shell 配置

- **脚本**: `03deployShellConfig.sh`
- **执行方式**: `bash linux/03deployShellConfig.sh`
- **前置条件**: 仓库已 clone（需要 `shell/deploy.sh`）
- **可跳过**: 是
- **说明**: 调用 `shell/deploy.sh` 部署 shell 配置片段到 `~/.bashrc.d/`

## 4. 安装应用程序

- **脚本**: `04installApps.ps1`
- **执行方式**: `pwsh linux/04installApps.ps1`
- **前置条件**: 步骤 2 完成（需要 PowerShell）
- **可跳过**: 是
- **说明**: 通过 Homebrew 安装开发工具，安装 bun、Docker 等

---

PowerShell 已就绪，继续执行跨平台安装：[docs/INSTALL.md](../docs/INSTALL.md)
