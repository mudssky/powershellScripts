# 配置 Carapace 与 Atuin 多 Shell Profile

## Goal

创建仓库本地 `repo-ops` Skill，作为本仓库工程操作约定的稳定入口；将 PowerShell、Bash、Zsh 接入 CLI 工具的完整流程下沉为独立 reference。随后按该流程接入 Carapace 参数补全与 Atuin 历史记录，并将其纳入 Windows/macOS 桌面 Core CLI 与 Linux Full `terminal-extras` 安装，使已安装工具在交互式 Shell 启动后可用，未安装时安静降级。

## Background

- Bash/Zsh 配置使用模块化片段：`shell/deploy.sh:7-8` 将 `shell/shared.d` 与 `shell/{bash,zsh}.d` 部署到 `~/.bashrc.d/`，不直接替换完整 rc 文件。
- 双 Shell 通用初始化应放在 `shell/shared.d/*.sh`；Shell 专属补全或键绑定放在 `shell/bash.d`、`shell/zsh.d`。依据：`.trellis/spec/shell-shared/package/index.md:3-20`。
- Zsh 已由 `shell/zsh.d/00-compinit.zsh:1-2` 初始化补全系统；不得为 Carapace 重复运行 `compinit`。
- PowerShell Full 模式在 `profile/features/environment.ps1:630-767` 集中探测和初始化外部工具；高成本初始化已有 7 天文件缓存模式。
- PowerShell OnIdle 当前在 `profile/core/loadModule.ps1:113-126` 注册 fzf 历史键和 Tab=`Complete`；Carapace 官方要求 Tab 使用 `MenuComplete`，因此会改变现有补全交互。
- 现有 Bash/Zsh/PowerShell fzf 历史入口均为 `Alt+h`，不会直接占用 Atuin 默认的 `Ctrl+r` 或 Up 键：`shell/bash.d/fzf-history.sh:71`、`shell/zsh.d/fzf-history.zsh:67-68`、`psutils/modules/functions.psm1:293-310`。
- Carapace 官方当前初始化命令为 Bash/Zsh `source <(carapace _carapace)`、PowerShell `carapace _carapace | Out-String | Invoke-Expression`；PowerShell 必须使用 PSReadLine `MenuComplete`。
- Atuin 官方当前支持 `atuin init bash|zsh|powershell`，默认安装历史记录 hooks，并可绑定 `Ctrl+r`、Up 键；`--disable-up-arrow` 可保留原生 Up 键行为。
- 仓库当前没有 Carapace/Atuin 的活动配置或安装清单；仅归档脚本残留一段旧 Atuin 安装代码，不作为现行入口。
- 本机当前未安装 `carapace` 与 `atuin`，因此实现验证必须包含缺失工具降级路径；真实功能 smoke 需使用临时可执行 fixture 或可用环境。
- 仓库安装入口不是新增平台脚本，而是 `profile/installer/apps-config.json` 清单；Windows/macOS/Linux 的既有 `05installCoreCli.ps1` 分别从 Scoop/Homebrew 清单选择 `core + cli`。
- 用户已决定桌面环境进入 Core：Windows 与 macOS 自动安装 Carapace、Atuin；Linux Core 保持精简，两项工具仅在 Full 的 `terminal-extras` 自动安装。

## Requirements

### R1. 仓库本地 `repo-ops` Skill

- Skill 路径固定为 `.agents/skills/repo-ops/`，使用中文主体内容，作为本仓库工程操作约定的入口；当前只固化已有明确需求，不预造未使用的流程分支。
- `SKILL.md` 保持精简：说明仓库事实优先、先读对应 Trellis spec、按 reference 路由、验证后交付；Shell Profile 工具接入的细节不得堆在主文件。
- 当前流程单独存放为 `references/shell-profile-integration.md`，覆盖 PowerShell/Bash/Zsh CLI 初始化、补全、历史、提示符、键位、延迟加载和相关安装清单修改。
- Shell Profile reference 必须指向 `.trellis/spec/profile/package/`、`.trellis/spec/shell-shared/package/`、`.trellis/spec/infra/*-install-pipeline.md`、`profile/**`、`shell/**` 和对应测试，并约束重复初始化检查、加载归属、安静降级、PowerShell 缓存/OnIdle、统一安装清单和验证矩阵。
- 不保留 `.agents/skills/powershellscripts-shell-profile/` 别名或重复入口；实施时干净迁移现有草稿，避免两个 Skill 同时触发。
- Skill 不复制产品代码、包名表或生成脚本；reference 保存稳定流程与判断规则，具体软件事实仍以仓库清单、规范和测试为准。

### R2. Bash 与 Zsh 配置

- Carapace 与 Atuin 仅在交互式 Shell 且对应命令存在时初始化。
- 双 Shell 共享规则放入 `shell/shared.d`；仅当初始化语法或加载顺序确实不同，才使用 `shell/bash.d` / `shell/zsh.d` 专属片段。
- Zsh 复用已有 `00-compinit.zsh`，不得重复执行 `compinit`。
- 初始化不得直接写 `~/.bashrc` 或 `~/.zshrc`；继续由 `shell/deploy.sh` 管理片段。
- 重复 source 不应累积重复初始化、重复 hooks 或明显错误。
- Atuin 统一使用 `--disable-up-arrow`：接管 `Ctrl+r`，保留三套 Shell 原生 Up 键历史导航与现有 `Alt+h` fzf 历史入口。

### R3. PowerShell 配置

- 只影响 Full 模式；Minimal 与 UltraMinimal 不执行 Carapace/Atuin 外部进程初始化。
- 使用现有批量命令探测与错误隔离模式；工具缺失时不阻断 profile。
- Carapace 初始化成功时，PSReadLine Tab 使用 `MenuComplete`；Carapace 缺失或初始化失败时保留现有 `Complete`，并更新相应测试与 README。
- Atuin 使用 `--disable-up-arrow`，与现有 `Alt+h` fzf 历史入口共存；失败仅告警，不阻断其他工具或基础 profile。
- Carapace 与 Atuin 的生成脚本均复用 `Invoke-WithFileCache`，按平台隔离缓存，并使用会话状态避免重复初始化。

### R4. 安装清单

- Windows 在 Scoop 清单加入 `atuin` 与 Extras bucket 的 `carapace-bin`，标记 `supportOs: ["Windows"]` 和 `core + cli`，由现有 `windows/05installCoreCli.ps1` 安装；当前 Core 精确集合从 10 项更新为 12 项，通用安装链必须确保清单声明的 `extras` bucket 可用。
- macOS 在 Homebrew 清单加入 `carapace` 与 `atuin`，标记 `supportOs: ["macOS"]` 和 `core + cli`，由现有 `macos/05installCoreCli.ps1` 安装。
- Linux 在 Homebrew 清单加入独立的 `supportOs: ["Linux"]` 条目，标记 `cli + terminal-extras`，由现有 `linux/08installFullApps.ps1` 安装；Linux Core 不选择两项工具。
- 不新增 Carapace/Atuin 专属平台安装脚本，不在叶子脚本内维护第二份包名；Windows 所需 Scoop bucket 通过既有通用安装模块处理。

### R5. 文档与验证

- 更新 profile/shell 相关说明，明确两项工具的加载位置、快捷键行为、缺失工具降级和部署方式。
- 增加或更新可观察行为测试：命令探测、Full/Minimal/UltraMinimal 分流、PowerShell Tab 契约、Shell 语法与交互式守护、重复加载。
- 完成实现后运行 `pnpm qa` 与 `pnpm test:pwsh:all`；另对 Bash/Zsh 片段分别执行语法检查和 source smoke。
- 安装清单测试必须验证 Windows/macOS Core 选择包含 Carapace 与 Atuin，Linux Core 不包含、Linux Full `terminal-extras` 包含两项工具，并覆盖 Scoop Extras bucket 前置。

## Acceptance Criteria

- [ ] AC1：仓库中存在可被项目 Agent 发现的 `.agents/skills/repo-ops/SKILL.md`；Shell Profile 请求会明确路由到 `references/shell-profile-integration.md`，旧 Skill 路径不存在且无重复触发入口。
- [ ] AC2：安装 Carapace 后，PowerShell、Bash、Zsh 的参数补全均在交互式会话中可用；未安装时三套 profile 正常启动且无硬错误。
- [ ] AC3：安装 Atuin 后，PowerShell、Bash、Zsh 均记录并搜索历史；`Ctrl+r` 打开 Atuin，Up 键保持原生历史导航，现有 `Alt+h` fzf 历史入口仍可用。
- [ ] AC4：PowerShell Minimal/UltraMinimal 不启动 Carapace 或 Atuin 子进程；Full 模式初始化失败时只影响对应工具。
- [ ] AC5：Zsh 仅初始化一次 completion system；Bash/Zsh 片段重复 source 不产生重复 hooks 或报错。
- [ ] AC6：README/Skill 中描述的命令、加载顺序、快捷键与实际实现一致。
- [ ] AC7：项目质量门禁、PowerShell 全量测试以及 Bash/Zsh 语法与 source smoke 全部通过。
- [ ] AC8：Windows 与 macOS Core 安装选择包含 Carapace 与 Atuin；Linux Core 不包含、Linux Full `terminal-extras` 包含两项工具；三端继续复用既有 `05`/`08` 安装入口。

## Out of Scope

- 自动登录 Atuin、启用同步、写入账号或密钥。
- 修改 Atuin 服务端、数据库或同步策略。
- 覆盖用户完整 `~/.bashrc`、`~/.zshrc` 或 `$PROFILE`。
- 将历史归档脚本恢复为安装入口。
- 为 Fish、Nushell、Xonsh、Cmd 或其他 Shell 增加配置。
- 不新增 Carapace/Atuin 专属平台安装脚本；安装统一通过现有清单与平台 Core/Full 入口。


