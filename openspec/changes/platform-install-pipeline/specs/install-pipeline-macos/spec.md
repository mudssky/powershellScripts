## ADDED Requirements

### Requirement: macOS 安装脚本编号规范
`macos/` 目录 SHALL 包含按编号排序的安装脚本，每个脚本职责单一。

#### Scenario: 完整脚本列表
- **WHEN** 列出 `macos/` 目录下的编号脚本
- **THEN** SHALL 按以下顺序包含：
  - `01installHomeBrew.sh` — 仅安装 Homebrew
  - `02installPowerShell.sh` — 安装 PowerShell（`brew install --cask powershell`）
  - `03deployShellConfig.sh` — 调用 `shell/deploy.sh` + symlink `.zshrc`
  - `04installApps.ps1` — 安装 Homebrew 应用
  - `05deployHammerspoon.sh` — 部署 Hammerspoon 配置

#### Scenario: Homebrew 和 PowerShell 职责分离
- **WHEN** 查看 `01installHomeBrew.sh` 内容
- **THEN** SHALL 仅包含 Homebrew 安装逻辑
- **THEN** SHALL 不包含 PowerShell 安装和 `.zshrc` 配置逻辑

#### Scenario: Shell 配置部署脚本
- **WHEN** 执行 `03deployShellConfig.sh`
- **THEN** SHALL 调用 `shell/deploy.sh` 部署 `~/.bashrc.d/` 片段
- **THEN** SHALL 将 `macos/config/.zshrc` symlink 到 `~/.zshrc`

#### Scenario: Hammerspoon 部署脚本
- **WHEN** 执行 `05deployHammerspoon.sh`
- **THEN** SHALL 调用 `hammerspoon/load_scripts.zsh` 部署 Hammerspoon 配置到 `~/.hammerspoon/`

### Requirement: macOS INSTALL.md manifest
`macos/INSTALL.md` SHALL 作为安装流水线的 manifest 文档，描述完整的安装流程。

#### Scenario: manifest 文档结构
- **WHEN** 查看 `macos/INSTALL.md`
- **THEN** 每个安装步骤 SHALL 包含以下字段：脚本名、执行方式、前置条件、是否可跳过、说明

#### Scenario: 仓库拉取指引
- **WHEN** 查看 `macos/INSTALL.md` 的第 0 步
- **THEN** SHALL 包含通过 `git clone` 拉取仓库的完整命令（无独立脚本，手动执行）

#### Scenario: 步骤顺序与脚本编号一致
- **WHEN** AI agent 按 INSTALL.md 中的步骤顺序执行
- **THEN** 每个步骤对应的脚本编号 SHALL 与文档中的步骤编号一致

#### Scenario: 前置条件声明
- **WHEN** 某个步骤依赖前一步骤的产出
- **THEN** INSTALL.md 中该步骤的"前置条件"字段 SHALL 明确声明此依赖
