## ADDED Requirements

### Requirement: macOS 安装脚本编号规范

`macos/` 目录 SHALL 按跨平台逻辑编号提供可独立执行的叶子脚本。

#### Scenario: 完整脚本列表

- **WHEN** 列出 `macos/` 目录下的编号脚本
- **THEN** SHALL 按以下顺序包含 `00bootstrap.zsh`、`01installHomebrew.zsh`、`02installPowerShell.zsh`、`03configureSources.zsh`、`04deployShellConfig.zsh`、`05installCoreCli.ps1`、`06installFonts.ps1`、`07installProfileTools.ps1`、`08installFullApps.ps1`、`09deployHammerspoon.zsh`、`10configureLoginItems.zsh`、`11installQuickActions.zsh` 与 `99verifyInstall.zsh`
- **THEN** 旧编号入口 SHALL 不作为兼容 shim 保留

#### Scenario: Core 与 Full 预设

- **WHEN** 使用默认 Core
- **THEN** SHALL 执行 `03`～`07` 与 `99 --preset Core`
- **WHEN** 显式使用 Full
- **THEN** SHALL 在 Core 上追加 `08`～`11` 与 `99 --preset Full`

#### Scenario: 应用单一真源

- **WHEN** `05`、`06`、`08` 或 `99` 选择软件
- **THEN** SHALL 从 `profile/installer/apps-config.json` 读取标签
- **THEN** SHALL 不维护第二份硬编码包名列表

#### Scenario: 预览和幂等

- **WHEN** zsh 叶子接收 `--dry-run` 或 PowerShell 叶子接收 `-WhatIf`
- **THEN** SHALL 不安装软件、不写用户配置、不启动 GUI
- **WHEN** Hammerspoon 或 Quick Action 目标内容未变化
- **THEN** SHALL 不重复写入或创建备份

### Requirement: macOS INSTALL.md manifest

`macos/INSTALL.md` SHALL 描述 Stage 0、Stage 1、Core/Full、网络模式、独立叶子、回滚和只读验证。

#### Scenario: 推荐入口

- **WHEN** 用户在已有仓库或新机执行 macOS 安装
- **THEN** 文档 SHALL 推荐 `macos/00bootstrap.zsh` 或根 `install.ps1 -Preset Core|Full`
- **THEN** 远程 bootstrap SHALL 说明 shallow clone 行为

#### Scenario: 验证入口

- **WHEN** 用户运行 `macos/99verifyInstall.zsh`
- **THEN** SHALL 支持 `--preset Core|Full`、`--step` 与 `--output-format json`
- **THEN** JSON stdout SHALL 只包含一个 document

#### Scenario: 末尾引导至跨平台安装

- **WHEN** 完成 macOS 平台步骤
- **THEN** 文档末尾 SHALL 包含指向 `docs/INSTALL.md` 的相对链接
