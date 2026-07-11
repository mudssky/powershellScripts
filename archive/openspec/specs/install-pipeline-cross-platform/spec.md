## ADDED Requirements

### Requirement: 跨平台安装总入口文档

`docs/INSTALL.md` SHALL 作为项目的安装总入口，串联平台安装和 PowerShell 层安装。

#### Scenario: 文档结构

- **WHEN** 查看 `docs/INSTALL.md`
- **THEN** SHALL 包含两个阶段：第一阶段引导到平台 INSTALL.md（linux/macOS），第二阶段描述跨平台 PowerShell 层安装步骤

#### Scenario: 平台引导

- **WHEN** 查看第一阶段内容
- **THEN** SHALL 包含指向 `linux/INSTALL.md` 和 `macos/INSTALL.md` 的相对链接

#### Scenario: PowerShell 层安装步骤

- **WHEN** 查看第二阶段内容
- **THEN** SHALL 按顺序包含以下步骤，每步使用与平台 INSTALL.md 相同的字段格式（脚本名、执行方式、前置条件、可跳过、说明）：
  1. `install.ps1` — 项目环境初始化（PATH + bin sync + Node build）
  2. `install.ps1 -installApp` — 安装应用程序
  3. `profile/installer/installModules.ps1` — 安装 PowerShell 模块

### Requirement: 平台文档末尾引导回总入口

平台 `INSTALL.md`（linux/macOS）的末尾 SHALL 引导用户返回 `docs/INSTALL.md` 继续跨平台安装。

#### Scenario: Linux INSTALL.md 末尾引导

- **WHEN** 完成 `linux/INSTALL.md` 的所有步骤
- **THEN** 文档末尾 SHALL 包含指向 `docs/INSTALL.md` 的链接，提示"PowerShell 已就绪，继续执行跨平台安装"

#### Scenario: macOS INSTALL.md 末尾引导

- **WHEN** 完成 `macos/INSTALL.md` 的所有步骤
- **THEN** 文档末尾 SHALL 包含指向 `docs/INSTALL.md` 的链接，提示"PowerShell 已就绪，继续执行跨平台安装"

### Requirement: README.md 引用安装指南

根目录 `README.md` SHALL 包含指向 `docs/INSTALL.md` 的安装指南引用。

#### Scenario: README 中的安装引用

- **WHEN** 查看根目录 `README.md`
- **THEN** SHALL 包含指向 `docs/INSTALL.md` 的相对链接

### Requirement: install.ps1 路径更新

根目录 `install.ps1` 中引用的 shell 配置部署脚本路径 SHALL 更新为 `shell/deploy.sh`。

#### Scenario: 路径引用正确

- **WHEN** 查看 `install.ps1` 中的 shell 配置部署逻辑
- **THEN** SHALL 引用 `shell/deploy.sh` 而非 `linux/01manage-shell-snippet.sh`
