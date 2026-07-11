# macOS 安装步骤审计

## 结论

macOS 现有链路可以作为三平台参考实现，但不宜直接把 `01`～`08` 串起来当作最终预设。当前主要问题不是缺少总入口，而是叶子步骤职责混合、执行契约不一致，以及验证脚本的顺序和覆盖范围落后于实际安装需求。

用户已确认稳定逻辑步骤 ID，并一次性重排物理文件：

`bootstrap -> package-manager -> pwsh -> sources -> shell -> core-cli -> fonts -> profile-modules-tools -> full-apps -> hammerspoon -> login-items -> quick-actions -> verify`

用户已确认 Core 为默认预设：执行到 `profile-modules-tools` 后做 Core 验证；Full 在此基础上增加 GUI 与 macOS 集成项。预设只负责选择步骤，不复制叶子脚本业务逻辑。

## 已执行审计

- `zsh -n`、`bash -n` 和 PowerShell parser 静态检查均通过。
- 只读运行 `macos/06verifyInstall.zsh` 得到 `18 passed, 2 warned, 14 failed`；当前机器缺少 `blueutil`、Mos、Hammerspoon 托管配置与 manifest、登录项及 Finder Quick Action。
- `macos/05deployHammerspoon.sh --dry-run --no-launch`、`macos/08installQuickActions.zsh --dry-run` 与 `shell/deploy.sh --shell zsh --dry-run` 能正常预览。
- `macos/07configureLoginItems.zsh --dry-run` 仍会通过 AppleScript 解析真实应用，在解析 Mos 时阻塞；测试进程已终止，未写入系统配置。
- Context7 的 Homebrew 官方资料确认自动化安装可使用 `NONINTERACTIVE=1`，安装后应执行实际 Homebrew 二进制输出的 `brew shellenv`；默认 prefix 为 Apple Silicon 的 `/opt/homebrew` 或 Intel macOS 的 `/usr/local`。
- Context7 未收录 chsrc 官方条目。本机 `chsrc 0.2.2` 的只读 `list`/`set -dry` 显示其可覆盖多种源，但 Homebrew 会直接写 `~/.zshrc` 与 `~/.bashrc`，且部分 target 不支持 reset；因此 source 步骤必须由专门任务封装。

## 现有步骤矩阵

| 现有入口 | 当前职责与证据 | 主要问题 | 建议优化 | 目标逻辑步骤 |
|---|---|---|---|---|
| `01installHomeBrew.sh` | 检测 `brew`，不存在时直接执行官方安装脚本（`macos/01installHomeBrew.sh:6-19`） | 无严格错误模式、参数、curl/macOS 前检、preview；安装后当前进程未加载 `brew shellenv`；默认交互语义不明确 | 增加 `set -euo pipefail`、help、dry-run、交互/非交互显式参数；按 `/opt/homebrew`、`/usr/local` 查找新安装二进制，执行 `eval "$(brew shellenv)"` 并验证 `brew --prefix`；镜像只委托 sources/Stage 0 例外 | `package-manager` |
| `02installPowerShell.sh` | `pwsh` 不存在时执行 `brew install --cask powershell`（`macos/02installPowerShell.sh:6-19`） | 默认假设当前 PATH 已有 brew；不检查 PowerShell 7 基线；无 preview 和安装后验证 | 复用 Homebrew 探测与 shellenv；支持 dry-run；以 `pwsh -NoProfile` 和最低主版本验证；已安装但版本不满足时给出升级动作 | `pwsh` |
| `03deployShellConfig.sh` | 定位并调用 `shell/deploy.sh --shell zsh`（`macos/03deployShellConfig.sh:6-17`） | 修改仓库脚本执行位；不透传 dry-run/exclude；缺文件只打印 Warning 且最终可能返回成功 | 不执行 `chmod`；缺文件返回 1；显式透传受支持参数并保留 zsh 平台约束；依赖 `shell/deploy.sh` 自身作为唯一实现 | `shell` |
| `04installApps.ps1` | 先无条件运行字体脚本，再安装带 `macbook` 标签且非字体的 Homebrew 项（`macos/04installApps.ps1:2-13`） | 字体、核心 CLI、GUI 应用混合；无脚本级 `SupportsShouldProcess`；没有 `macbook` 标签但适用于 macOS 的 CLI 被静默跳过；不能形成 Core/Full | 拆成 core CLI、fonts、GUI apps 三个叶子入口；复用同一 `apps-config.json`，补明确分类标签；全部支持 `-WhatIf`；聚合单项失败并返回可判定结果 | `core-cli`、`fonts`、`gui-apps` |
| `05deployHammerspoon.sh` | 薄包装 `hammerspoon/load_scripts.zsh` 并透传参数（`macos/05deployHammerspoon.sh:6-17`） | 包装层仍修改源码执行位；loader 每次覆盖前都会备份，即使内容未变化（`macos/hammerspoon/load_scripts.zsh:65-98`） | 包装层不 chmod；loader 先比较内容，只在真实变更时备份和复制；未知参数使用退出码 2；保留 manifest、本机覆盖和 `--no-launch` | `hammerspoon` |
| `06verifyInstall.zsh` | 只读验证 repo、brew、pwsh、shell、apps、Hammerspoon、登录项和 Quick Action（`macos/06verifyInstall.zsh:17-18`、`:491-557`） | 文件编号位于后续安装步骤之前；apps 检查是少量硬编码；缺 sources、fonts、modules、Profile、bin、repo tools；无 Core/Full 严格度 | 作为逻辑 `verify`/建议物理 `99`；增加 `--preset Core|Full`、新增步骤检查与可选结构化结果；单步验证仍保留；WARN/FAIL 由预设决定 | `verify` |
| `07configureLoginItems.zsh` | 为 Hammerspoon、Mos 创建登录项，支持 dry-run（`macos/07configureLoginItems.zsh:17-18`、`:67-185`） | dry-run 仍解析真实 App；`path to application` 可能阻塞；只支持添加，不能撤销 | dry-run 不调用 AppleScript 查找应用；真实模式优先固定路径并为动态查找设置边界；增加 remove/uninstall；逐项汇总失败与权限提示 | `login-items` |
| `08installQuickActions.zsh` | 管理一个 Finder workflow，支持 dry-run 和 uninstall（`macos/08installQuickActions.zsh:12-17`、`:133-181`） | 覆盖前直接 `rm -rf`，没有时间戳备份；注释称批量但实现只有单个 workflow；复制与配置中途失败可能留下半成品 | 先校验源，再备份已有目标；在临时目录配置并验证后替换；使用 manifest/声明数组支持多个 workflow，或把文案收敛为单项；保留 uninstall | `quick-actions` |

## 缺失叶子步骤

| 逻辑步骤 | 复用资产 | 建议边界 | 默认预设 |
|---|---|---|---|
| `bootstrap` | 新增极薄 `macos/00bootstrap.zsh` | 检查系统与网络，获得 Git/Homebrew/PowerShell/chsrc 所需最小能力，然后调用根 Stage 1；不承载应用清单 | Stage 0 |
| `sources` | `chsrc`、`Switch-Mirrors.ps1`、新增 source adapter | 默认 `Direct` 不改源；显式 `China` 集中换源；可选 `Auto` 探测后按条件换源。状态、备份和恢复由独立子任务实现 | Core/Full 共用但可无操作 |
| `core-cli` | `apps-config.json`、`Install-PackageManagerApps` | 只安装 shell/Profile/仓库工具直接依赖与用户明确标为核心的 CLI；不包含 GUI | Core/Full |
| `fonts` | `profile/installer/installFont.ps1` | 独立 WhatIf、幂等和验证；不再作为 app 安装的隐式副作用 | Core/Full |
| `profile-modules-tools` | `installModules.ps1`、Profile 入口、`Manage-BinScripts.ps1`、根 `install.ps1` 的 Bash/Node 构建 | 分别调用现有实现并汇总结果；不在平台脚本复制构建或 Profile 逻辑 | Core/Full |
| `gui-apps` | `apps-config.json`、`Install-PackageManagerApps` | 只安装 macOS GUI/cask 与可选平台工具；与 Hammerspoon 配置部署分离 | Full |

## 标准步骤契约

其他平台应复用下列元数据，而不是照搬 macOS 文件名：

| 字段 | 含义 |
|---|---|
| `Id` | 跨平台稳定逻辑 ID，不依赖文件编号 |
| `Command` / `VerifyCommand` | 真实叶子入口与只读验证入口 |
| `Platforms` / `Presets` | 支持平台以及 Core/Full 归属 |
| `Prerequisites` | 依赖的步骤 ID、命令或系统能力 |
| `Critical` / `Skippable` | 失败是否中止，以及显式跳过规则 |
| `RequiresElevation` / `Interactive` | 是否需要 sudo/admin、GUI 权限或用户确认 |
| `SupportsPreview` | 支持 dry-run/WhatIf 的方式与限制 |
| `NetworkTargets` | 该步骤消费哪些已准备好的 package source，不负责自行换源 |
| `Rollback` | 备份、卸载或恢复入口；不可自动回滚时给出明确说明 |

统一编排器应将每步结果归一为 `Succeeded`、`Skipped`、`Failed` 或 `Blocked`，并记录耗时、退出码和错误摘要。`Install-PackageManagerApps` 当前会捕获单项异常后继续且无结构化返回（`psutils/modules/install.psm1:425-472`），在用于预设前必须补充汇总契约，否则总入口无法可靠判断“部分安装失败”。

## 已确认编号

| 编号 | 跨平台语义 | macOS 目标入口 |
|---|---|---|
| `00` | bootstrap | `00bootstrap.zsh` |
| `01` | package-manager | `01installHomebrew.zsh` |
| `02` | pwsh | `02installPowerShell.zsh`，安装命令可由 Stage 0 helper 包装 |
| `03` | sources | `03configureSources.zsh`，只作平台薄入口，核心逻辑由网络源任务提供 |
| `04` | shell | `04deployShellConfig.zsh` |
| `05` | core-cli | `05installCoreCli.ps1` |
| `06` | fonts | `06installFonts.ps1` |
| `07` | profile/tools | `07installProfileTools.ps1` |
| `08` | full-apps | `08installFullApps.ps1` |
| `09` | platform automation | `09deployHammerspoon.zsh` |
| `10` | login-items | `10configureLoginItems.zsh` |
| `11` | desktop integration | `11installQuickActions.zsh` |
| `99` | verify | `99verifyInstall.zsh` |

旧文件采用一次性重命名，所有仓内引用在同一变更中更新，不保留长期兼容 shim。其他平台保持相同编号语义；不支持的步骤由步骤元数据标记不可用或跳过，不复制无意义的平台实现。

## 建议实施顺序

1. 按已确认的默认 Core、显式 Full 边界实现步骤选择与验证规则。
2. 新增 `00`、`03`，并将 Homebrew、PowerShell、shell 入口重排为 `01`、`02`、`04`，统一错误、参数、preview 与验证契约。
3. 将旧 `04` 拆为 `05` core CLI、`06` fonts、`08` GUI apps，新增 `07` Profile/tools，并补应用清单分类。
4. 将 Hammerspoon、登录项和 Quick Action 重排为 `09`、`10`、`11`，优化幂等、备份与撤销能力。
5. 将旧 `06` 重排为 `99`，扩展验证覆盖新逻辑步骤，最后交给根统一编排器接入预设。

## 已确认预设

- `Core`（默认）：`01`～`07` 加 `99 --preset Core`；覆盖 Homebrew、source 准备、PowerShell、shell、核心 CLI、字体、PowerShell Profile/模块和仓库工具。
- `Full`：Core 加 `08`～`11`，最后执行 `99 --preset Full`；覆盖 GUI 应用、Hammerspoon、登录项和 Finder Quick Actions。
- `00bootstrap.zsh` 是 Stage 0 入口，不属于 Core/Full 的业务步骤集合。
