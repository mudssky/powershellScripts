# Windows 安装流水线

## 目标

为 Windows 新增与 macOS、Linux/WSL 同规格的两阶段安装流水线：Stage 0 在 Windows PowerShell 5.1 中获得 Git、PowerShell 7、Scoop 与仓库，并把本次运行所需的机器级操作合并为一次受限提升；Stage 1 由根 `install.ps1` 连续执行 source、Core/Full CLI、字体、Profile/仓库工具、AutoHotkey 用户配置和只读验证，同时把 WSL 宿主职责收敛到显式 opt-in 入口。

## 背景

- 根步骤注册表已经声明 Windows 的 `03/05/06/07/08/09/99` 路径，但顶层 `windows/` 尚不存在，Windows 仍依赖根 `install.ps1` 的旧式混合逻辑。
- `profile/installer/apps-config.json` 当前有 59 个未分层的 Scoop 项、1 个默认跳过的 winget 项和 5 个默认跳过的 Chocolatey 项，不能直接等价为 Core。
- `profile/installer/installFont.ps1` 已使用 Scoop nerd-fonts bucket 安装 JetBrains Mono 与 Fira Code；`scripts/ahk/**` 已具备 AutoHotkey v2 脚本、构建和用户启动项目标，但旧入口包含提示、直接启动和难以测试的副作用。
- `linux/wsl2/.wslconfig` 与 `loadWslConfig.ps1` 仍位于 Linux 目录，且旧脚本会覆盖配置后直接执行 `wsl --shutdown`；Linux 客体流水线已经明确宿主职责应迁到 `windows/wsl/`。
- `Invoke-PackageSourceBootstrap.ps1` 已提供 Windows PowerShell 5.1 兼容的 winget source snapshot/restore；Stage 1 事务引擎已支持 npm、pnpm、pip、go 等 Windows target。
- 官方 PowerShell 文档推荐通过 winget 安装 `Microsoft.PowerShell`，并提供 MSI 静默安装参数；winget 在较旧 Windows Server 上并非稳定前置，因此 Stage 0 仍需要官方 MSI fallback。
- 官方 WSL 文档确认 `.wslconfig` 位于 `%UserProfile%`、作用于所有 WSL2 发行版，而 `wsl --shutdown` 会立即终止所有运行中的发行版。

## 依赖

- `07-10-macos-install-pipeline`：编号、预设、退出码和验证合同。
- `07-10-network-source-bootstrap`：winget Stage 0 helper 与共享 source 事务。
- `07-10-unified-install-orchestrator`：根 Stage 1、步骤选择和 Auto restore。
- `07-10-linux-wsl-install-pipeline`：WSL 客体入口、重启与宿主移交合同。

## 已确认决策

- Windows 11 22H2+ x64 完整支持；Windows 10 22H2 x64 支持 Core/Full，但 Windows 11 专属 WSL 能力按 capability 跳过。
- Windows ARM64 本期只识别并返回 Blocked/10；Windows Server/CI 只承诺平台模型、WhatIf 和只读验证。
- Stage 1 主进程始终保持普通用户上下文。Scoop、Profile、bin、AutoHotkey 用户启动项和其他用户配置不得在提升进程中执行。
- 机器级命令只由隔离提升 helper 执行。`Unattended` 最多允许一次 UAC 确认；`NonInteractive` 不能无提示提升时返回 Blocked/10。
- Scoop 是 Core CLI 主真源；winget 负责 Stage 0 和后续明确批准的系统安装器/GUI；Chocolatey 只保留显式兼容入口。
- Core 基线为 zoxide、fnm、starship、fzf、ripgrep、jq、uv、bat、fd 和 eza。Full 追加明确标记的 terminal extras，未分类 Scoop 项不默认安装。
- 首版 Full 的默认桌面自动化只包含 AutoHotkey v2 与现有 `scripts/ahk` 配置。EarTrumpet、Twinkle Tray、Neovide 等保持显式可选或 `skipInstall`。
- WSL 安装、发行版管理和 `.wslconfig` 部署仅由显式 `IncludeWsl` 启用，不属于默认 Core/Full；流水线绝不自动执行 `wsl --shutdown`。
- 自动化硬门禁使用 Windows CI、fixture、WhatIf 和只读验证；真实干净 Windows 11 Core 安装作为后续手工 smoke，不阻塞首轮归档。

## 需求

### 平台与公共合同

- 新增共享 Windows 平台模型，稳定返回 edition/build、architecture、是否 Server、管理员状态、winget/App Installer、PowerShell、Scoop 和 WSL capability。
- 所有变更叶子支持 `-WhatIf`；退出码固定为 0 成功/已满足/内部跳过、1 失败、2 参数错误、10 Blocked。
- Windows 10 不得误用 Windows 11 专属 `.wslconfig` 设置；ARM64 与 Server 不得误走 x64 Scoop、字体、AutoHotkey 或 WSL 真实安装链。
- 若 Stage 1 从提升后的 PowerShell 启动，涉及用户配置的步骤必须返回 10，并提示改用普通用户终端。

### Stage 0

- `windows/00quickstart.ps1` 必须兼容 Windows PowerShell 5.1，支持 repo URL/目录、Preset、NetworkMode、本地 Git/PowerShell/AutoHotkey 安装包、交互等级、`IncludeWsl` 和 WhatIf。
- 远程模式默认使用 `git clone --depth=1`；已有开发 clone 只复用，不 pull、不改变 shallow 状态。
- Stage 0 必须在提升前完成本次运行的机器级预检：缺少的 Git、PowerShell 7、Full 所需 AutoHotkey v2，以及显式 `IncludeWsl` 所需的 WSL 安装共同进入一个 operation plan，通过最多一次隔离提升执行，然后刷新当前进程 PATH。
- 远程模式先下载 `windows/bootstrap/bootstrap-manifest.psd1`，再按清单下载并校验 00 所需的 bootstrap 模块、提升 helper、winget source helper、bootstrap source 配置和 Windows package 配置；clone 前不得隐式引用仓库内尚不存在的文件。
- winget 可用时优先安装 `Microsoft.PowerShell`；winget 不可用且为 Direct 时允许官方 x64 MSI fallback。China/Auto 缺少可恢复 adapter 或本地安装包时返回 10，不静默回退 Direct。
- Scoop 安装保持普通用户上下文。China/Auto 缺 Scoop 且没有本地 installer 时返回 10；已有 Scoop 时不改写用户 buckets 或配置。
- PowerShell 7 可用后立即移交根 Stage 1；00 不维护第二份 `03`～`99` 步骤图，也不向根编排器新增 `IncludeWsl` 参数。

### 编号叶子与预设

- 新增 `00/01/02/03/05/06/07/08/09/99` Windows 入口；04、10、11 继续由步骤注册表标记为不支持，不创建空脚本。
- `01` 负责 Scoop 探测与普通用户安装；`02` 负责 PowerShell 7 安装/验证，二者可独立执行并复用 Stage 0 bootstrap 模块。
- `03` 组合 winget capability/status 与 npm、pnpm、pip、go 等共享 source target，JSON stdout 保持单文档。
- `05` 从 `profile/installer/apps-config.json` 选择 `Windows + core + cli` 的 Scoop 项；winget 不作为 Core 隐式 fallback。
- `06` 复用 Scoop nerd-fonts bucket，安装 JetBrains Mono Nerd Font 与 Fira Code Nerd Font，并以用户字体/包状态验证。
- `07` 复用共享 Profile Tools，增加 Windows PATH 刷新与根/bin 持久化；不得复制 Profile、模块、Node/pnpm、bin 和 Node build 逻辑。
- `08` 只追加 `Windows + cli + terminal-extras` 的 Scoop 项；GUI 软件首版不自动加入。
- `09` 验证 AutoHotkey v2，构建现有 AHK 脚本并部署当前用户 Startup；独立执行且缺少 AHK 时可自行构造一次受限提升，但经 00 进入 Full 时必须复用 Stage 0 已完成状态，不得再次弹 UAC。旧脚本的 ReadKey、隐式提示和直接退出不得泄漏。
- `99` 只读验证平台、repo、pwsh、Scoop、winget、sources、Core/Full CLI、字体、Profile、PATH、AutoHotkey 和可选 WSL。

### 包与 source 所有权

- Scoop、winget、Chocolatey 同一软件只能有一个默认安装所有者；Chocolatey 条目不进入 Core/Full。
- Core 只标记确认的 10 个基础 CLI；Full 只追加明确 terminal-extras。其余 Scoop 项继续可由弃用的 `-installApp` 显式全量入口访问。
- 字体、Scoop bucket、Stage 0 package ID 和 WSL 默认值使用 Windows 声明式配置；远程 Stage 0 只保留无法访问仓库配置时必需的最小常量。
- winget source 修改继续使用结构化 cmdlets 与 snapshot，不解析 `winget source list` 表格；共享 Stage 1 source 引擎仍将 winget 标为 Unsupported，`03` 只读报告 capability/snapshot 状态。
- Auto 模式的 winget 安装命令在 Stage 0 helper 包装内临时切换并恢复；China 模式保留首次 snapshot 和 Restore 提示；共享语言 target 继续由根 source 事务恢复。

### 权限、PATH 与重启

- 提升 helper 只接受受限的机器级 operation plan，不执行任意脚本文本，不写用户配置，并把结构化结果写回普通用户进程。
- UAC 取消、严格非交互无法提升、提升命令失败、系统重启或新终端要求均返回可操作的 Blocked/10。
- Scoop、winget、MSI 或用户 PATH 变化后，当前进程从 User/Machine PATH 重新构造环境；只有无法在当前进程生效的组件才要求重开终端。
- `Unattended` 在一次 00 调用中最多触发一次 UAC；Git、PowerShell、Full/AHK 与 IncludeWsl 的机器操作必须在该次提升前全部规划，后续叶子只复用或报告 Blocked，不重复弹窗。

### WSL 宿主边界

- `windows/wsl/` 拥有 WSL 安装需求建模、发行版管理、`.wslconfig` 和宿主到 `linux/00quickstart.sh` 的移交入口；00 负责把需要提升的 WSL 安装 operation 合并到总计划，根 Stage 1 不接收 `IncludeWsl`。
- `IncludeWsl` 未选择时不得启用功能、安装发行版、写 `.wslconfig` 或中断现有 WSL。
- `.wslconfig` 按 `windows-packages.psd1` 中每个配置键的 capability/build 元数据生成有效内容，Windows 10 不写入未满足前置的键；内容相同不备份，变化时创建可读时间戳 `.bak` 并原子替换，然后返回 10，提示用户手工执行 `wsl --shutdown` 后重跑。
- `wsl --install --no-launch`、系统功能或发行版安装要求 Windows 重启时立即停止 WSL 后续动作并返回 10。
- Windows 99 即使未选择 IncludeWsl，也可只读报告已有 WSL 与 Linux 客体移交状态；WSL 缺失不影响默认 Core/Full 成功。

### 测试与文档

- `windows-latest` 执行 Stage 0 fixture、平台矩阵、全部叶子 WhatIf、99 单文档 JSON 和根 Core/Full 参数链。
- 自动化测试使用临时 USERPROFILE、fake winget/scoop/msiexec/wsl、临时 Startup 与配置目标，不执行真实安装、UAC、字体写入、AHK 启动或 WSL shutdown。
- 文档提供干净 Windows 11 的手工 Core smoke checklist，明确 UAC、PATH 刷新、Blocked/10 与重跑位置。

## 验收标准

- [ ] 干净 Windows 11 x64 有明确 Stage 0 命令；远程最小资产可在 clone 前完整下载并校验，且不存在对未下载仓库文件的隐式依赖。
- [ ] 一次 00 调用中的 Git、PowerShell、Full/AHK 与 IncludeWsl 机器操作最多使用一次 UAC，并有失败、重启和重跑提示。
- [ ] Windows 11、Windows 10、ARM64 与 Server/CI 在统一平台模型中得到稳定的 Full/Partial/Blocked 结果。
- [ ] 远程 bootstrap 使用 shallow clone，已有开发 clone 保持完整历史。
- [ ] 普通用户 Stage 1 不会因机器级步骤改变 Scoop、Profile、Startup 或用户配置归属。
- [ ] `03/05/06/07/08/09/99` 可独立执行并由根编排器调用，WhatIf 无真实副作用。
- [ ] Core 只安装确认的 10 个基础 CLI；Full 只追加明确 terminal-extras 和 AutoHotkey，不默认安装其他 GUI。
- [ ] JetBrains Mono 与 Fira Code Nerd Font 可幂等安装和验证。
- [ ] AutoHotkey v2 与当前用户 Startup 可幂等部署，旧入口不再阻塞等待按键。
- [ ] 未选择 IncludeWsl 时不改变 WSL；显式 WSL 配置变化可备份、原子替换并以退出 10 提示手工 shutdown。
- [ ] 99 输出单文档 JSON，默认验证保持只读，WSL 缺失不导致默认 Core 失败。
- [ ] Windows CI 在零真实安装副作用下覆盖 Stage 0、Core/Full、权限、重启与 WSL opt-in 参数链。
- [ ] 文档包含真实 Windows 11 Core smoke checklist，并明确其为后续运行态验证。
- [ ] 实施前已补齐并审阅 `design.md` 与 `implement.md`。

## 范围外

- Windows ARM64、Windows Server 的完整软件、GUI、UAC 和 WSL 安装支持。
- 自动执行 `wsl --shutdown`、注销发行版、删除用户 WSL 数据或迁移 VHD。
- 默认安装 EarTrumpet、Twinkle Tray、Neovide、PowerToys 或其他未经重新确认的 GUI 软件。
- Home Manager、Nix、远程 WinRM/PSRP 装机、MDM/Autopilot 和 Windows 系统策略管理。
- 自动化 CI 中执行真实包安装、UAC、字体注册、Startup 写入或系统重启。
