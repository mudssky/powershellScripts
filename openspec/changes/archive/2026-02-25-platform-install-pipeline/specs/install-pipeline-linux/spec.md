## ADDED Requirements

### Requirement: Linux 安装脚本编号规范

`linux/` 目录 SHALL 包含按编号排序的安装脚本，每个脚本职责单一。

#### Scenario: 完整脚本列表

- **WHEN** 列出 `linux/` 目录下的编号脚本
- **THEN** SHALL 按以下顺序包含：
  - `00quickstart.sh` — 拉取仓库
  - `01installHomeBrew.sh` — 仅安装 Homebrew
  - `02installPowerShell.sh` — 仅安装 PowerShell
  - `03deployShellConfig.sh` — 调用 `shell/deploy.sh` 部署 shell 配置
  - `04installApps.ps1` — 安装应用程序

#### Scenario: Homebrew 和 PowerShell 职责分离

- **WHEN** 查看 `01installHomeBrew.sh` 内容
- **THEN** SHALL 仅包含 Homebrew 安装和环境变量配置逻辑
- **THEN** SHALL 不包含 PowerShell 安装逻辑

#### Scenario: PowerShell 独立安装脚本

- **WHEN** 查看 `02installPowerShell.sh` 内容
- **THEN** SHALL 包含本地 deb 安装和 fallback 到 installer 脚本的逻辑（从原 `02installHomeBrew.sh` 拆出）

#### Scenario: Shell 配置部署脚本

- **WHEN** 执行 `03deployShellConfig.sh`
- **THEN** SHALL 调用 `shell/deploy.sh` 完成 `~/.bashrc.d/` 的部署

### Requirement: Linux INSTALL.md manifest

`linux/INSTALL.md` SHALL 作为安装流水线的 manifest 文档，描述完整的安装流程。

#### Scenario: manifest 文档结构

- **WHEN** 查看 `linux/INSTALL.md`
- **THEN** 每个安装步骤 SHALL 包含以下字段：脚本名、执行方式、前置条件、是否可跳过、说明

#### Scenario: 仓库拉取指引

- **WHEN** 查看 `linux/INSTALL.md` 的第 0 步
- **THEN** SHALL 包含通过 `gh` 或 `git clone` 拉取仓库的完整命令

#### Scenario: 步骤顺序与脚本编号一致

- **WHEN** AI agent 按 INSTALL.md 中的步骤顺序执行
- **THEN** 每个步骤对应的脚本编号 SHALL 与文档中的步骤编号一致

#### Scenario: 前置条件声明

- **WHEN** 某个步骤依赖前一步骤的产出（如 `04installApps.ps1` 依赖 PowerShell）
- **THEN** INSTALL.md 中该步骤的"前置条件"字段 SHALL 明确声明此依赖

#### Scenario: 末尾引导至跨平台安装

- **WHEN** 完成 `linux/INSTALL.md` 的所有步骤
- **THEN** 文档末尾 SHALL 包含指向 `docs/INSTALL.md` 的相对链接，引导继续跨平台 PowerShell 层安装
