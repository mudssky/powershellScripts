# 环境安装指南

本文档是项目的安装总入口，分为两个阶段：先完成平台基础环境安装，再执行跨平台 PowerShell 层安装。

## 第一阶段：平台基础环境

根据你的操作系统，先完成对应的平台安装：

- **Linux**: 参考 [linux/INSTALL.md](../linux/INSTALL.md)
- **macOS**: 参考 [macos/INSTALL.md](../macos/INSTALL.md)

完成后你将拥有：Homebrew、PowerShell、shell 配置。

## 第二阶段：跨平台 PowerShell 环境

以下步骤在所有平台通用，需要在 PowerShell 中执行。

### 1. 项目环境初始化

- **脚本**: `install.ps1`
- **执行方式**: `pwsh ./install.ps1`
- **前置条件**: PowerShell 已安装，仓库已 clone
- **可跳过**: 否
- **说明**: 配置 PATH、同步 bin shim、构建 Node.js 工具集

### 2. 安装应用程序

- **脚本**: `install.ps1 -installApp`
- **执行方式**: `pwsh ./install.ps1 -installApp`
- **前置条件**: 步骤 1 完成
- **可跳过**: 是（如不需要额外应用）
- **说明**: 通过 Homebrew/scoop/choco 安装开发工具

### 3. 安装 PowerShell 模块

- **脚本**: `profile/installer/installModules.ps1`
- **执行方式**: `pwsh ./profile/installer/installModules.ps1`
- **前置条件**: 步骤 1 完成
- **可跳过**: 是
- **说明**: 安装 Pester 等 PowerShell 模块
