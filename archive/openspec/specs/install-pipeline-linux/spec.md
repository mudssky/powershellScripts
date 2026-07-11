## ADDED Requirements

### Requirement: Linux 与 WSL 两阶段安装流水线

`linux/` 目录 SHALL 为 Ubuntu/Debian 与 WSL 客体提供 Stage 0、编号 Stage 1 叶子和只读验证。

#### Scenario: 标准入口与编号

- **WHEN** 列出 Linux 安装入口
- **THEN** SHALL 包含 `00quickstart.sh`、`01installHomeBrew.sh`、`02installPowerShell.sh`、`03configureSources.sh`、`04deployShellConfig.sh`、`05installCoreCli.ps1`、`06installFonts.ps1`、`07installProfileTools.ps1`、`08installFullApps.ps1` 与 `99verifyInstall.ps1`
- **THEN** Linux 不适用的 `09`～`11` SHALL 由统一步骤注册表标记为不支持

#### Scenario: Stage 0 移交

- **WHEN** 在 Ubuntu/Debian 或对应 WSL 客体执行 `00quickstart.sh`
- **THEN** SHALL 准备最小 Git、Linuxbrew 与 PowerShell 7 后调用根 `install.ps1 -Preset Core|Full`
- **THEN** 远程 clone SHALL 默认使用 `--depth=1`
- **THEN** China/Auto 前置不足 SHALL 返回 Blocked，不得静默回退 Direct

### Requirement: Linux 软件与 source 单一真源

#### Scenario: 系统包和 CLI 所有权

- **WHEN** 安装 apt 系统包、Docker 或桌面字体
- **THEN** SHALL 从 `config/install/linux-packages.psd1` 读取声明
- **WHEN** 安装 Core CLI 或 Full terminal extras
- **THEN** SHALL 从 `profile/installer/apps-config.json` 读取 Linux 标签
- **THEN** 同一软件 SHALL NOT 同时由 apt 与 Linuxbrew 声明

#### Scenario: Source 事务

- **WHEN** 执行 `03configureSources.sh`
- **THEN** SHALL 根据 `/etc/os-release` 选择 ubuntu、debian 或 arch target
- **THEN** SHALL 委托共享 package source 引擎处理 Direct、China、Auto、snapshot 与 Restore

### Requirement: WSL 客体边界

#### Scenario: 客体配置与宿主重启

- **WHEN** `/etc/wsl.conf` 内容需要变化
- **THEN** SHALL 在变化时创建时间戳备份并原子替换
- **THEN** SHALL 返回 Blocked/10 并提示在 Windows 执行 `wsl --shutdown`
- **THEN** Linux 客体流水线 SHALL NOT 写 `.wslconfig`、Windows 用户目录或执行宿主重启

#### Scenario: Docker 复用

- **WHEN** `docker info` 已成功
- **THEN** SHALL 复用当前 Docker Desktop 集成或客体 Engine
- **WHEN** Docker 不可用且平台受支持
- **THEN** SHALL 使用发行版系统包安装并验证客体 Docker Engine
- **THEN** 当前用户需要新增 `docker` 组权限时 SHALL 返回 Blocked/10，并提示重新登录或重启 WSL 后重跑

### Requirement: Linux 预设与验证

#### Scenario: Core、Full 与字体

- **WHEN** 执行 Core
- **THEN** SHALL 安装核心 CLI、Profile/工具与 Docker，服务器和普通 WSL 默认跳过字体
- **WHEN** 执行 Full
- **THEN** SHALL 只追加 Linux terminal extras，不安装 GUI 应用
- **WHEN** 显式选择 Desktop 字体模式
- **THEN** SHALL 使用发行版字体包并更新 fontconfig 缓存

#### Scenario: 只读验证

- **WHEN** 执行 `99verifyInstall.ps1 -OutputFormat Json`
- **THEN** stdout SHALL 只包含一个 JSON document
- **THEN** 验证 SHALL 从共享应用与系统包清单读取期望，不维护第二份包名
- **THEN** Arch、ARM 与未满足的 WSL 重启 SHALL 返回明确 Blocked
