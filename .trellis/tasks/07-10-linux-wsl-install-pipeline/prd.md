# Linux WSL 安装流水线

## 目标

按照已经落地的 macOS 步骤合同，为 Ubuntu/Debian 与 WSL 客体提供可连续执行、可预览、可重跑和可验证的安装流水线，同时让 Arch、ARM 与 Windows 宿主职责得到明确分流。

## 背景

- 当前 `linux/00`～`04`、`linux/ubuntu/**`、`linux/archlinux/**` 与 `linux/wsl2/**` 存在重复安装逻辑、硬编码镜像、直接写 shell rc 和宿主/客体职责混合。
- 根 `install.ps1`、`config/install/steps.psd1`、package source 事务引擎与 macOS 叶子合同已经提供 Stage 1 的步骤图、退出码和恢复协议，本任务只补 Linux 平台业务。
- 首期主要使用场景是无 GUI 的 Linux 服务器与 WSL。Windows Terminal 在宿主侧渲染终端字体；WSLg、PDF、图片或浏览器渲染仍可能需要 Linux 字体，但不属于默认 WSL 路径。
- 本任务依赖已完成的 `07-10-macos-install-pipeline`、`07-10-network-source-bootstrap` 与 `07-10-unified-install-orchestrator`。

## 已确认事实

- 首期完整平台矩阵为 Ubuntu/Debian、WSL 客体、`x86_64/amd64`。
- Arch 是次要平台，本期只保证识别、步骤分流和明确的 `Supported`/`Blocked` 结果。
- `arm64/aarch64` 本期只保证识别和明确阻断，不承诺 PowerShell、Linuxbrew 与 Docker 的完整安装链。
- Ubuntu/Debian 与 WSL 使用 `apt`/`dpkg` 管理系统级软件，Linuxbrew 管理跨平台 CLI。
- Core 默认安装 Linuxbrew，以复用 `profile/installer/apps-config.json` 中的跨平台软件选择。
- Linux Full 不安装 GUI 应用，只增加 `terminal-extras` 等适用于 Linux 的高级 CLI。
- WSL 优先复用已经可用的 Docker，包括 Docker Desktop 集成；缺少可用 Docker 时才安装客体内 Docker Engine。
- `linux/wsl/` 只拥有发行版客体配置；`.wslconfig`、WSL 安装和 shutdown/restart 属于 Windows 流水线。

## 需求

### 平台与步骤合同

- 物理编号沿用 `00/01/02/03/04/05/06/07/08/09/10/11/99`；Linux 不适用的 `09`～`11` 继续由步骤注册表标记为不支持，不创建空脚本。
- Ubuntu/Debian 与 WSL 客体必须能够从 Stage 0 进入根 `install.ps1 -Preset Core|Full`，编号叶子也必须可独立执行。
- 所有变更叶子支持 `--dry-run` 或 `-WhatIf`；退出码固定为 0 成功/已满足/内部跳过、1 失败、2 参数错误、10 Blocked。
- 动态的 `Skipped`/`NotApplicable` 作为叶子内部组件结果返回；根编排器在叶子退出 0 时仍可把整个步骤视为成功。
- 发行版、WSL、桌面能力和 CPU 架构必须通过共享平台探测得到，不允许各叶子维护不同判断。

### Stage 0

- `linux/00quickstart.sh` 作为 Linux Stage 0，允许覆盖 repo URL、目标目录、Preset、NetworkMode 和交互等级。
- 远程获取仓库默认执行 `git clone --depth=1`；已有完整开发 clone 不改写历史或 shallow 状态。
- Stage 0 只负责最小 `apt` 前置、Git、Linuxbrew、PowerShell 7 和向根 Stage 1 移交，不保存第二份 Core/Full 步骤图。
- Direct 可使用官方 apt/GitHub/Homebrew 路径；China/Auto 在 Git、PowerShell 或系统 apt 前置尚未满足且缺少可恢复 Stage 0 adapter 时必须返回 Blocked，不得静默回退 Direct。
- China/Auto 允许通过 repo URL 覆盖、已有 PowerShell 7 或本地 PowerShell deb 包解除对应 Blocked 条件。

### 包与源所有权

- `config/install/linux-packages.psd1` 作为 Stage 1 Linux 系统包真源；`apps-config.json` 继续作为 Linuxbrew CLI 真源，同一软件不得在两者重复声明。
- 系统基础依赖、PowerShell、Docker 和 Linux 字体使用 `apt`/`dpkg`；Core CLI 和 Full terminal extras 使用 Linuxbrew。
- `03 sources` 在系统包与 CLI 安装前调用共享事务引擎，按 `/etc/os-release` 选择 `ubuntu`、`debian` 或 `arch` target，并准备 Linuxbrew 与受支持的语言生态 target。
- `config/network/package-sources.json` 的 `brew` target 必须显式支持 Linux；任何镜像 URL 仍由 package source catalog 拥有。
- Auto 的事务恢复继续由根编排器负责；Linux 叶子不得自行重置用户已有 source。

### Shell、Profile 与预设

- `04 shell` 只包装 `shell/deploy.sh`，默认选择当前 bash/zsh，不修改仓库脚本执行位。
- Linuxbrew shellenv 通过受管 shell 片段加载，不由安装脚本直接追加 `~/.bashrc` 或 `~/.zshrc`。
- `05 core-cli` 从 `apps-config.json` 选择 `Linux + core + cli`。
- `06 fonts` 支持 `Auto`、`Desktop`、`Server`；无桌面服务器和普通 WSL 默认内部跳过，桌面模式使用发行版原生字体包并更新字体缓存。
- `07 profile-tools` 复用 PowerShell 模块、Profile、Node/pnpm、bin、Bash/Node 构建能力，不复制 macOS 已有公共逻辑；Linux 额外负责系统工具、Docker 与 WSL 客体配置。
- `08 full-apps` 只选择 `Linux + cli + terminal-extras`；没有候选时内部返回 NotApplicable，不移植 macOS cask 或未经确认的 Linux GUI 软件。

### WSL 与 Docker

- WSL 客体流水线不得修改 Windows 用户目录，不得执行 `wsl --shutdown`。
- 部署 `/etc/wsl.conf` 前必须比较内容；未变化不备份，变化时创建可读时间戳 `.bak` 后原子替换。
- `/etc/wsl.conf` 变化后返回 Blocked/10，并输出 Windows 宿主应执行的 `wsl --shutdown` 与重跑命令。
- Docker 满足条件必须以实际 `docker info`/daemon 可用性判断，不能只看 CLI 是否存在。
- Docker Desktop 集成可用时不安装客体 Engine；否则在 Ubuntu/Debian 使用系统包真源安装并验证 Docker Engine、Compose 与 systemd 服务。

### 验证与旧入口

- `99verifyInstall.ps1` 只读，支持 Core/Full、单步骤和 Text/Json 输出；JSON stdout 必须只有一个 document。
- 验证覆盖平台支持、repo、pwsh、brew、sources、shell、Core/Full CLI、Profile/工具、Docker 和 WSL 客体配置。
- 现有 `linux/03deployShellConfig.sh`、`linux/04installApps.ps1` 若需兼容，只能成为指向新叶子的弃用薄包装，不保留旧业务逻辑。
- `linux/ubuntu/**`、`linux/archlinux/**` 与 `linux/wsl2/**` 中不再被引用的历史实现，由独立 `07-10-repository-archive-batch` 决定物理迁移；本任务不提前移动其他归档候选。

## 验收标准

- [x] Ubuntu/Debian 与 WSL 客体在 amd64 上可从 Stage 0 完成 Core，并可使用根编排器重跑单步或断点续跑。
- [x] Arch 与 arm64/aarch64 不会误走 amd64 apt 安装链，所有不支持路径均返回可操作的 Blocked 结果。
- [x] Stage 0 远程 clone 使用 shallow history，已有开发 clone 保持原状；China/Auto 前置不足时不会静默使用 Direct。
- [x] 系统包和 Linuxbrew CLI 分属两个单一真源，Core/Full 选择结果无重复软件。
- [x] `03 sources` 能选择正确发行版 target，并遵循 Direct/China/Auto 事务与恢复合同。
- [x] 普通服务器与 WSL 默认不安装字体；显式 Desktop 模式可安装并验证 Linux 字体缓存。
- [x] Linux Full 只安装高级 CLI，不安装 GUI 或 macOS cask。
- [x] WSL 已有可用 Docker 时不重复安装；需要客体 Engine 时可安装并验证，配置变化会阻断并提示宿主重启。
- [x] `/etc/wsl.conf` 只在变化时备份和原子替换，流水线不写 `.wslconfig` 或调用 `wsl --shutdown`。
- [x] `99` 能报告缺失阶段，单文档 JSON 可直接解析，默认验证没有写操作。
- [x] 自动化测试使用临时 HOME、伪命令、fixture 系统文件与目标路径，不执行真实 apt、Docker、source Apply 或 `/etc` 写入。

## 范围外

- Linux GUI 应用、桌面自动化、登录项与桌面集成。
- Arch、ARM Linux 的完整安装实现，以及 pacman/yay 软件清单重写。
- Windows 宿主的 WSL 安装、`.wslconfig`、资源配置和 shutdown/restart。
- Docker registry 镜像的强制配置；本期只处理 Docker Engine 的安装与可用性。
- 旧 Linux/WSL 文件向根 `archive/` 的物理迁移与 QA 排除。
