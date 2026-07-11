# Linux WSL 安装流水线技术设计

## 目标与边界

本任务把 Ubuntu/Debian 与 WSL 客体接入现有两阶段安装模型。根编排器继续拥有步骤图和运行状态，Linux 叶子只拥有发行版探测、apt/Linuxbrew、WSL 客体配置、Docker 和平台验证。

以下能力不在 Linux 叶子重复实现：

- Core/Full 选择、Step/FromStep/SkipStep、Auto restore 和汇总由根 `install.ps1` 与 `InstallOrchestrator.psm1` 负责。
- 镜像 URL、snapshot、drift 检查和 Restore 由 package source 引擎负责。
- CLI 标签选择与安装结果由 `psutils/modules/install.psm1` 负责。
- Profile、模块、bin 与仓库构建的跨平台主体抽到共享 Profile Tools 模块。
- Windows 宿主 WSL 生命周期由后续 Windows 任务负责。

## 执行流

```text
linux/00quickstart.sh
  -> detect distro / WSL / architecture / interaction mode
  -> satisfy minimal apt + Git prerequisites when Direct permits
  -> shallow clone or reuse current repo
  -> linux/01installHomeBrew.sh
  -> linux/02installPowerShell.sh
  -> pwsh ./install.ps1 -Preset Core|Full ...
       -> 03 distro + brew + language sources
       -> 04 bash/zsh managed shell snippets
       -> 05 Linuxbrew Core CLI
       -> 06 font environment decision
       -> 07 shared Profile/tools + Linux system tools + Docker + WSL guest config
       -> [Full] 08 Linuxbrew terminal extras
       -> 09/10/11 registry-level Skipped
       -> 99 read-only verification
```

Stage 0 不维护 03～99 的列表。PowerShell 7 可用后，控制权立即交给根入口。

## 文件与所有权

| 步骤 | 标准入口 | 职责 |
|---|---|---|
| 00 | `linux/00quickstart.sh` | 最小 apt/Git、clone、Stage 0 顺序与 Stage 1 移交 |
| 01 | `linux/01installHomeBrew.sh` | Linuxbrew 探测、安装、当前进程 shellenv |
| 02 | `linux/02installPowerShell.sh` | amd64 PowerShell 7、本地 deb、安装后验证 |
| 03 | `linux/03configureSources.sh` | 发行版 target 与共享 source 事务薄入口 |
| 04 | `linux/04deployShellConfig.sh` | 包装 `shell/deploy.sh` |
| 05 | `linux/05installCoreCli.ps1` | `Linux + core + cli` |
| 06 | `linux/06installFonts.ps1` | Auto/Desktop/Server 与原生字体包 |
| 07 | `linux/07installProfileTools.ps1` | 公共 Profile/tools、系统工具、Docker、WSL 客体配置 |
| 08 | `linux/08installFullApps.ps1` | `Linux + cli + terminal-extras` |
| 99 | `linux/99verifyInstall.ps1` | 只读 Text/Json 平台验证 |

共享实现：

- `linux/lib/install-common.sh`：Bash 叶子共用的日志、参数值校验、发行版/WSL/架构和 sudo 预检。
- `linux/pwsh/LinuxInstall.psm1`：PowerShell 叶子共用的平台模型、系统包计划、Docker/WSL 操作与验证结果。
- `linux/pwsh/Test-InstallState.ps1`：从应用清单与平台模块生成 99 的结构化检查结果。
- `scripts/pwsh/install/ProfileTools.psm1`：从现有 macOS 07 抽取真正跨平台的 Profile、模块、Node/pnpm、bin 和构建逻辑，macOS 与 Linux 包装共同调用。
- `config/install/linux-packages.psd1`：Ubuntu/Debian Stage 1 系统包、Docker 和桌面字体声明。
- `shell/shared.d/homebrew.sh`：只检测已知 Homebrew prefix 并加载 `brew shellenv`，不包含镜像值。

## 平台模型

`Get-LinuxInstallEnvironment` 返回稳定对象：

```text
DistributionId: ubuntu | debian | arch | unknown
DistributionFamily: debian | arch | unknown
Architecture: amd64 | arm64 | unknown
IsWsl: bool
HasDesktop: bool
HasSystemd: bool
SupportLevel: Full | Partial | Blocked
```

探测输入默认来自 `/etc/os-release`、`uname -m`、`WSL_INTEROP`/`WSL_DISTRO_NAME` 与 `/proc/version`。模块允许测试覆盖这些路径和值，但生产入口不依赖调用方伪造平台。

支持矩阵：

| 环境 | Stage 0 | 03/04/05/08 | 06 | 07/99 |
|---|---|---|---|---|
| Ubuntu/Debian amd64 | Full | Full | Server 默认跳过，Desktop 支持 | Full |
| WSL Ubuntu/Debian amd64 | Full | Full | 默认跳过 | Full，含 guest config |
| Arch amd64 | Blocked 或已有前置时部分移交 | 每步按能力 Supported/Blocked | 默认跳过 | 只读报告，不承诺完整安装 |
| arm64/aarch64 | Blocked | 不进入完整安装 | 只读识别 | 只读报告 |
| unknown distro | Blocked | shell/verify 可按能力运行，其余阻断 | 阻断 | 只读报告 |

## Stage 0 设计

### 公共参数

```bash
bash linux/00quickstart.sh \
  [--repo-url <url>] [--repo-dir <path>] \
  [--preset Core|Full] [--network-mode Direct|China|Auto] \
  [--powershell-package <deb>] \
  [--unattended|--non-interactive] [--dry-run]
```

- 默认 repo dir 为用户目录下稳定路径；已有仓库只校验，不 pull、不改变 history。
- `--unattended` 可在开始时执行一次 `sudo -v`；`--non-interactive` 只允许 `sudo -n true`，不满足返回 10。
- dry-run 不调用 apt、curl installer、git clone、dpkg 或根 Stage 1，只打印参数数组形式的计划。

### 网络边界

- Direct：允许通过 apt 获得最小前置，并使用官方 Homebrew/PowerShell 下载路径。
- China/Auto：Linuxbrew 安装命令可由 `package-source-bootstrap.sh --target brew` 注入受管环境。
- Git 缺失且需要 apt、PowerShell 缺失且没有本地 deb、或 repo 无法通过覆盖 URL 获取时，China/Auto 返回 Blocked；不执行隐藏 Direct fallback。
- source catalog 的 `brew.platforms` 扩展为 `macos, linux`，managed-env adapter 本身保持不写真实 shell rc。

### PowerShell

- 已有 `pwsh` 必须通过 `pwsh -NoProfile` 验证主版本至少为 7。
- 本地 deb 优先，路径由 `--powershell-package` 显式提供；安装在临时工作目录完成，不扫描仓库中的任意 deb。
- 官方下载路径只在 Direct 使用，按 amd64 release artifact 安装；arm64、未知发行版和非 Direct 无本地包路径返回 10。
- 安装完成后不启动交互 shell，只输出版本并返回。

## Stage 1 源

`03configureSources.sh` 读取平台模型并构造一次共享调用：

```text
Phase: Runtime
Targets: <ubuntu|debian|arch>, brew, npm, pnpm, pip, go
TransactionId: root orchestrator supplied value
```

- Direct 返回结构化 no-op。
- China/Auto 中任一 required target Blocked 时步骤返回 10；不在叶子中删除已创建事务。
- Docker registry target 不进入默认列表。本期 Docker 安装使用发行版包，registry mirror 仍为显式可选能力。
- JSON stdout 只包含 Switch-Mirrors 返回的单一 document；诊断写 stderr。

## 软件包所有权

### 系统包

`linux-packages.psd1` 只使用 data literal，并按发行版族声明：

- `CoreSystem`：07 所需系统工具和服务依赖。
- `Docker`：Docker Engine 与 Compose 的发行版包/候选包。
- `DesktopFonts`：仅 Desktop 模式使用的字体包。

Stage 0 的极小 Git/curl/ca-certificates/build prerequisite 仍写在 Bash Stage 0，因为此时 PowerShell 无法解析 psd1；这些包不得同时作为 Linuxbrew CLI 声明。

### Linuxbrew 应用

- 05：`RequiredTag @('core', 'cli')`、`TargetOS Linux`。
- 08：`RequiredTag @('cli', 'terminal-extras')`、`TargetOS Linux`。
- `skipInstall: true` 始终优先。
- 包安装逐项继续，required failure 使叶子退出 1。
- 执行前从固定 prefix 或 PATH 恢复 brew 环境；没有 brew 返回 Blocked 10，不隐式重跑 Stage 0。

## Shell 与 Profile Tools

### Shell

04 只负责参数适配：bash 叶子接收根编排器的 `--preset`、交互标记与 `--dry-run`，然后调用 `shell/deploy.sh --shell bash|zsh`。shellenv 由 `homebrew.sh` 片段动态加载，安装脚本不直接编辑 rc。

### 共享 Profile Tools

`ProfileTools.psm1` 返回组件结果，不自行 exit：

1. `installModules.ps1 -Platform <macOS|Linux>`。
2. `profile/profile.ps1 -LoadProfile`。
3. fnm Node LTS。
4. 根 `packageManager` 对应 pnpm。
5. `Manage-BinScripts.ps1 -Action sync -Force`。
6. Bash build。
7. Node install/build。
8. uv/nbstripout。

macOS 07 与 Linux 07 只负责传平台和追加平台组件，避免复制现有约 07 的命令链。公共模块保留 WhatIf、结构化状态和 Failed > Blocked > success 的退出优先级。

## 字体

`06installFonts.ps1 -Environment Auto|Desktop|Server`：

- Auto 在 WSL 中选择 Server；在明确的 XDG desktop/Wayland/X11 环境中选择 Desktop；证据不足时选择 Server。
- Server/普通 WSL 返回内部 `Skipped/NotApplicable`，脚本退出 0。
- Desktop 从系统包真源安装字体，随后运行 `fc-cache` 并验证期望 family；WhatIf 只输出计划。
- Windows Terminal 字体不由 WSL 客体管理。需要 WSLg 或无头渲染时，用户可直接运行叶子并指定 Desktop。

## Docker 与 WSL 客体配置

### Docker

07 先执行 `docker info`：

- 成功：记录 AlreadyPresent，不区分 Docker Desktop 或原生 Engine，不重复安装。
- CLI 缺失或 daemon 不可用：Ubuntu/Debian 从系统包真源安装客体 Engine 和 Compose。
- WSL 安装客体 Engine 前要求 `/etc/wsl.conf` 启用 systemd；需要重启时先完成配置写入并返回 Blocked，不继续启动 Docker。
- 安装后通过 `systemctl enable --now docker` 启动服务；当前用户尚无 daemon 权限时加入 `docker` 组，以 sudo 验证 daemon，并返回 10，要求原生 Linux 重新登录或 WSL 宿主重启后重跑。
- 严格非交互 sudo 预检失败时立即返回 10，不再执行 apt、WSL 配置或其他特权步骤。

### 客体配置

- 模板移动到 `linux/wsl/wsl.conf`。
- 写入流程：读取目标 -> 内容相同则 AlreadyPresent -> 同目录临时文件 -> 语法/关键字段检查 -> 时间戳备份 -> 原子替换。
- 测试可覆盖目标路径和 privileged command runner；生产默认目标固定 `/etc/wsl.conf`。
- 内容变化返回一个 `RestartRequired` 组件，07 最终退出 10，消息只建议在 Windows 执行 `wsl --shutdown`。

## 验证

```powershell
pwsh linux/99verifyInstall.ps1 `
  [-Preset Core|Full] [-Step <id>] [-OutputFormat Text|Json]
```

结果字段至少包含 `Preset`、`Environment`、`Status`、`ExitCode`、`Counts`、`Results`。检查项从 `apps-config.json` 和 `linux-packages.psd1` 读取期望，不硬编码第二份包名。

整体优先级：Failed/1 > Blocked/10 > Succeeded/0。NotApplicable 不计为失败。Arch/ARM 的“当前任务不支持”是 Blocked，不伪装为已安装成功。

## 兼容与归档

- `install.ps1 -installApp` 的 Linux 兼容分支改为调用新 Core CLI 叶子，并继续发出弃用警告；不再 dot-source 旧混合脚本。
- 旧 03/04 入口若保留，仅做参数安全的弃用转发。
- 历史发行版 installer 不由新文档、Stage 0 或根编排器引用。物理归档延后到独立归档任务，避免跨任务修改未批准候选。

## 安全与回滚

- 测试与 WhatIf 不执行真实 sudo、apt、dpkg、Docker、source Apply 或 `/etc` 写入。
- shell rc、WSL config 与 package source 修改均只在内容变化时备份；source rollback 仍由事务 ID 管理。
- Docker 安装不删除现有 Docker Desktop 集成或用户 daemon 配置。
- 任何需要宿主重启、sudo 认证、未知发行版或不支持架构的路径返回 10，并提供可复制的下一步。
