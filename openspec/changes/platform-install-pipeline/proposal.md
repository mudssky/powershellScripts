## Why

当前项目的环境安装存在以下问题：(1) 没有统一的入口文档说明执行顺序和依赖关系，新环境搭建需要人工判断先后；(2) 部分脚本职责混合（如 `02installHomeBrew.sh` 同时安装 Homebrew 和 PowerShell）；(3) macOS 缺少 shell 配置部署和 Hammerspoon 配置等步骤；(4) AI agent 无法自动化执行完整的环境安装流程；(5) 缺少跨平台的 PowerShell 层安装文档——平台脚本安装完 pwsh 后，后续的 `install.ps1`（PATH + bin sync + Node build）、应用安装、PS 模块安装等跨平台步骤没有文档化。

本变更在 `shell-config-restructure` 之后执行，假设 `shell/deploy.sh` 已就位。

## What Changes

- 创建 `docs/INSTALL.md` 作为跨平台安装总入口，引导用户先完成平台安装再执行 PowerShell 层安装
- 更新根目录 `README.md` 引用 `docs/INSTALL.md`
- 拆分 `linux/02installHomeBrew.sh` 为独立的 Homebrew 安装和 PowerShell 安装两个脚本
- 重新编号 `linux/` 下的安装脚本，形成完整的 00-xx 流水线
- 补全 `macos/` 的安装步骤：添加 shell 配置部署（调用 `shell/deploy.sh`）和 Hammerspoon 配置部署
- 重新编号 `macos/` 下的安装脚本
- 为 `linux/` 和 `macos/` 各创建一个 `INSTALL.md` manifest 文档，描述每个脚本的用途、执行顺序、前置条件、是否可跳过
- 平台 `INSTALL.md` 开头包含仓库拉取指引，末尾引导回 `docs/INSTALL.md` 继续跨平台安装
- `docs/INSTALL.md` 包含 PowerShell 层的安装步骤：`install.ps1`（PATH + bin sync + Node build）、`install.ps1 -installApp`（应用安装）、`profile/installer/installModules.ps1`（PS 模块安装）

## Capabilities

### New Capabilities
- `install-pipeline-linux`: Linux 平台的完整安装流水线，包含按编号排序的脚本和 INSTALL.md manifest
- `install-pipeline-macos`: macOS 平台的完整安装流水线，包含按编号排序的脚本和 INSTALL.md manifest
- `install-pipeline-cross-platform`: 跨平台 PowerShell 层安装文档（`docs/INSTALL.md`），作为总入口串联平台安装和 PowerShell 层安装

### Modified Capabilities

（无已有 spec 需要修改）

## Impact

- **文件重命名/拆分**: `linux/02installHomeBrew.sh` 拆分为 Homebrew 和 PowerShell 两个独立脚本，所有脚本重新编号
- **新增文件**: `docs/INSTALL.md`（跨平台总入口）、`linux/INSTALL.md`、`macos/INSTALL.md`，以及 macOS 下新增的 shell 配置部署和 Hammerspoon 部署脚本
- **修改文件**: `README.md`（添加安装指南引用）、`install.ps1`（更新 `linux/01manage-shell-snippet.sh` 路径为 `shell/deploy.sh`）
- **依赖**: 假设 `shell-config-restructure` 已完成，`shell/deploy.sh` 可用
- **无破坏性变更**: 脚本功能不变，仅拆分和重新编号
