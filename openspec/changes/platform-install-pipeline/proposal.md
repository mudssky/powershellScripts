## Why

当前 `linux/` 和 `macos/` 目录下的安装脚本存在以下问题：(1) 没有统一的入口文档说明执行顺序和依赖关系，新环境搭建需要人工判断先后；(2) 部分脚本职责混合（如 `02installHomeBrew.sh` 同时安装 Homebrew 和 PowerShell）；(3) macOS 缺少 shell 配置部署和 Hammerspoon 配置等步骤；(4) AI agent 无法自动化执行完整的环境安装流程。需要为每个平台建立完整的、按编号排序的安装流水线，并提供 Markdown manifest 文档让 agent 可以按顺序执行。

本变更在 `shell-config-restructure` 之后执行，假设 `shell/deploy.sh` 已就位。

## What Changes

- 拆分 `linux/02installHomeBrew.sh` 为独立的 Homebrew 安装和 PowerShell 安装两个脚本
- 重新编号 `linux/` 下的安装脚本，形成完整的 00-xx 流水线
- 补全 `macos/` 的安装步骤：添加 shell 配置部署（调用 `shell/deploy.sh`）和 Hammerspoon 配置部署
- 重新编号 `macos/` 下的安装脚本
- 为 `linux/` 和 `macos/` 各创建一个 `INSTALL.md` manifest 文档，描述每个脚本的用途、执行顺序、前置条件、是否可跳过
- `INSTALL.md` 开头包含仓库拉取指引，方便通过 GitHub 网页文档引导 AI agent 从零开始安装

## Capabilities

### New Capabilities
- `install-pipeline-linux`: Linux 平台的完整安装流水线，包含按编号排序的脚本和 INSTALL.md manifest
- `install-pipeline-macos`: macOS 平台的完整安装流水线，包含按编号排序的脚本和 INSTALL.md manifest

### Modified Capabilities

（无已有 spec 需要修改）

## Impact

- **文件重命名/拆分**: `linux/02installHomeBrew.sh` 拆分为 Homebrew 和 PowerShell 两个独立脚本，所有脚本重新编号
- **新增文件**: `linux/INSTALL.md`、`macos/INSTALL.md`，以及 macOS 下新增的 shell 配置部署和 Hammerspoon 部署脚本
- **依赖**: 假设 `shell-config-restructure` 已完成，`shell/deploy.sh` 可用
- **无破坏性变更**: 脚本功能不变，仅拆分和重新编号
