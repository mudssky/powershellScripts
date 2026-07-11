# macOS 安装步骤审计与优化

## Goal

将 macOS 现有手工编号安装链整理为可连续执行、可单步重跑、可预览和可验证的参考实现，在不复制叶子业务逻辑的前提下，为统一 PowerShell 编排器以及后续 Windows、Linux/WSL 流水线提供稳定步骤契约。

## Background

- macOS 当前是三平台中最完整的链路，已有 Homebrew、PowerShell、shell、应用、Hammerspoon、登录项、Finder Quick Actions 和综合验证，但主要依赖 `macos/INSTALL.md` 手工串联。
- 现有脚本的严格错误、参数、dry-run、备份、幂等和退出语义不一致；`04installApps.ps1` 还混合字体、CLI 与 GUI，并以含义过宽的 `macbook` 标签筛选。
- 逐文件问题、只读验证结果和文件行号证据位于 `audit.md`。
- Homebrew 与首次无人值守边界位于 `research/unattended-bootstrap.md`；Core/Full 软件分类证据位于 `research/preset-package-classification.md`。

## Dependencies

- 本任务的步骤与参数契约先供 `07-10-network-source-bootstrap` 和 `07-10-unified-install-orchestrator` 使用。
- 代码实施前，网络源任务必须提供 macOS source adapter，统一编排器必须提供 Stage 1 调用接口；本任务不得为 `00` 或 `03` 增加临时重复编排逻辑。

## Requirements

### 步骤与编号

- 对旧 `01installHomeBrew.sh`、`02installPowerShell.sh`、`03deployShellConfig.sh`、`04installApps.ps1`、`05deployHammerspoon.sh`、`06verifyInstall.zsh`、`07configureLoginItems.zsh`、`08installQuickActions.zsh` 的审计问题逐项落实。
- 物理脚本一次性重排为统一编号语义：`00 bootstrap`、`01 package-manager`、`02 pwsh`、`03 sources`、`04 shell`、`05 core-cli`、`06 fonts`、`07 profile/tools`、`08 full-apps`、`09 platform automation`、`10 login-items`、`11 desktop integration`、`99 verify`。
- 编号表示跨平台阶段，文件名表示平台实现；Windows、Linux/WSL 后续沿用相同编号语义，不适用步骤通过元数据跳过。
- 旧入口在同一变更中重命名并更新全部仓内调用、文档、提示和规范，不长期保留兼容 shim；仓外未登记调用方不在兼容范围。
- 每个叶子步骤保持可独立执行；Core/Full 选择、依赖图、断点重跑和跨平台汇总由根编排器负责。

### 预设与应用真源

- 默认预设为 Core：package-manager、pwsh、sources、shell、core-cli、fonts、profile/tools 和 Core 验证；`00bootstrap` 只负责进入安装链。
- Full 必须显式选择，在 Core 上追加 full-apps、Hammerspoon、login-items、Quick Actions 和 Full 验证。
- `profile/installer/apps-config.json` 是唯一软件真源，继续复用 `tag` 数组：
  - `macbook`、`linuxserver` 表示场景；
  - `core`、`full` 表示预设；
  - `cli`、`font`、`gui`、`platform` 表示类别；
  - `terminal-extras`、`ai-cli` 表示显式可选组。
- 首期 Core CLI 固定为 `fnm`、`jq`、`fd`、`eza`、`ripgrep`、`fzf`、`zoxide`、`starship`、`bat`、`uv`；字体独立为 3 个已配置 Nerd Fonts。
- 有效但非默认的终端工具不归档、不删除，只保留显式组或单项入口。
- AI CLI 使用 `ai-cli`、`cli` 标签且不进入 Core/Full；npm/bun provider 去重不在本任务处理。
- `skipInstall: true` 始终优先；QA 必须检测 `core/full` 冲突、预设项类别缺失或重复、保留标签拼写错误。
- 根编排器、叶子脚本和验证入口都从同一 JSON 选择软件，不复制包名列表。

### Stage 0 与网络

- 新增薄 `macos/00bootstrap.zsh`：在本地或远程启动场景中获得 Git、仓库、Homebrew 和 PowerShell 7，然后移交根 Stage 1；它不保存 Core/Full 业务步骤列表。
- 远程启动场景默认使用 `git clone --depth=1` 获取完整工作树但不下载旧历史；允许覆盖 repo URL 与目标目录，需要历史时由用户显式 `git fetch --unshallow`。
- “首次无人值守”从 macOS 完成首次登录后开始：
  - 默认模式允许必要的 sudo、Homebrew、CLT fallback 和系统权限交互；
  - `--unattended` 允许开头一次管理员认证，随后无人值守完成 Core；
  - `--non-interactive` 严格零提示，只面向 MDM/CI/已预置机器，前置不足时快速返回 `Blocked`。
- 不保存管理员密码、不写宽泛 sudoers、不绕过 TCC/SIP/Gatekeeper；Full 的 GUI 权限前置不足时允许明确返回 `Blocked`。
- 网络模式默认 Direct，不修改 source；China 与 Auto 必须显式选择。
- Homebrew 安装后立即加载实际 prefix 的 `brew shellenv`；通过 Stage 0 获得 PowerShell 7 后立即移交根 Stage 1，由根编排器在正式批量安装前执行 `03 sources`。
- chsrc、镜像地址、source 状态、备份和恢复由网络源任务实现；macOS 叶子脚本不得硬编码镜像清单或直接向 shell rc 追加镜像变量。

### 叶子行为

- 修改状态的 zsh 脚本至少支持 help、dry-run 和明确参数错误；PowerShell 脚本使用 `SupportsShouldProcess`/WhatIf。
- 统一退出语义：成功或已满足为 0，执行/验证失败为 1，参数错误为 2，缺少外部权限或前置为 10（Blocked）。
- 重复执行不得因已有安装或相同内容产生额外备份、重复配置或误报失败。
- 修改用户配置前只在真实变化时创建可读时间戳 `.bak`；本机 local 配置继续遵循项目备份规则。
- `Install-PackageManagerApps` 必须把选择与副作用分离，支持标签过滤并返回逐项结构化结果；单项失败后继续同一步其他项，步骤结束时可靠报告 required failure。
- `04 shell` 只包装 `shell/deploy.sh --shell zsh`，不修改仓库执行位；shared deploy 修改 rc 前备份。
- `05`、`06`、`08` 分别按 `core+cli`、`core+font`、`full+gui/platform` 选择软件。
- `07 profile/tools` 复用现有 PowerShell 模块、`profile/profile.ps1 -LoadProfile`、fnm/Node/pnpm、`Manage-BinScripts.ps1`、Bash/Node 构建和 nbstripout 入口；macOS 不安装 Windows 专属 BurntToast。
- Hammerspoon 相同内容不备份或重写，继续以 loader/manifest 和 `config.local.lua` 为真源。
- 登录项 dry-run 不调用可能阻塞的应用解析，支持移除本脚本管理的项目。
- Quick Actions 覆盖前备份，在临时目录完成配置和 plutil 验证后替换，并保留 uninstall 与 runner/action 分层。

### 验证

- `99verifyInstall.zsh` 保持只读，支持 `--step`、`--preset Core|Full` 和根编排器可消费的结构化输出。
- Core 验证覆盖 repo、brew、sources、pwsh、shell、Core CLI、字体、PowerShell 模块/Profile、bin 和仓库工具；Full 追加 GUI、Hammerspoon manifest、登录项和 Quick Actions。
- PowerShell 可用后从 `apps-config.json` 动态读取期望项；pwsh 缺失时记录失败并跳过依赖 catalog 的检查，不维护硬编码第二名单。
- WARN 不改变退出码；必需项失败返回 1；因系统权限无法检查时报告明确的 Blocked/不可验证状态。

## Acceptance Criteria

- [ ] 旧 `01`～`08` 每个脚本的审计问题都有对应实现、验证或明确的任务边界。
- [ ] 新 `00`～`11`、`99` 职责无重叠，叶子可独立运行，编号可供另外两个平台复用。
- [ ] 默认 Core 与显式 Full 按同一应用真源选择，修改标签即可同步影响安装和验证。
- [ ] 已登录个人新机可在一次管理员认证后无人值守完成 Core；严格零提示模式不会挂起等待输入。
- [ ] 远程 Bootstrap 使用 shallow clone，本地仓库运行和手工开发 clone 不改变历史行为。
- [ ] Direct 不改源，China/Auto 只通过统一 source adapter 生效，叶子脚本不存在散落镜像 URL。
- [ ] dry-run/WhatIf 不写本机配置、不安装包、不启动 GUI；重复执行不制造无意义备份。
- [ ] 包安装部分失败可见且不会被误报为总体成功；依赖步骤能区分 Failed 与 Blocked。
- [ ] Core/Full 验证覆盖约定阶段，且软件期望值不维护第二份硬编码列表。
- [ ] 所有活动仓内引用已迁移到新编号，相关 Hammerspoon/Quick Actions 规范同步更新。
- [ ] PowerShell 全量测试和根 `pnpm qa` 通过，macOS 静态语法、dry-run 与 plist/workflow 检查通过。
- [ ] 用户已审阅 `audit.md`、`design.md`、`implement.md` 并明确批准后，任务才可进入 implementation。

## Out of Scope

- 根 `install.ps1` 的跨平台 Core/Full 编排器实现。
- chsrc 与其他 source adapter 的实现。
- Linux/WSL、Windows 或 Nix 叶子实现。
- 从开箱、Setup Assistant 或 MDM 控制面开始的零接触设备部署。
- AI CLI 的 npm/bun provider 去重。
- 仓外未登记旧脚本调用方的兼容 shim。
