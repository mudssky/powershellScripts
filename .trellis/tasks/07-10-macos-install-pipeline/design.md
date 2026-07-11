# macOS 安装流水线技术设计

## 目标与边界

本任务把 macOS 现有编号脚本整理为可独立执行的叶子步骤，并定义根统一编排器可调用的稳定契约。平台脚本只拥有 macOS 业务：Homebrew、macOS shell、字体与应用、Hammerspoon、登录项、Finder Quick Actions 和平台验证。

以下逻辑不在本任务重复实现：

- Core/Full 调度、步骤选择、断点重跑和跨平台汇总由 `07-10-unified-install-orchestrator` 负责。
- chsrc、镜像状态、备份和恢复由 `07-10-network-source-bootstrap` 负责。
- Linux/WSL 与 Windows 只复用编号和步骤契约，不复制 macOS 命令。
- Nix 不作为 macOS 原生安装步骤的隐藏后端。

## 总体架构

```text
远程或本地 00bootstrap.zsh
  -> 系统与交互模式预检
  -> 获得 Git/仓库
  -> 01 Homebrew
  -> 02 PowerShell 7
  -> 根 install.ps1 Stage 1
       -> 03 source adapter
       -> 04 shell
       -> 05 core CLI
       -> 06 fonts
       -> 07 Profile/modules/repo tools
       -> [Full] 08 apps -> 09 Hammerspoon -> 10 login items -> 11 Quick Actions
       -> 99 verify
```

`00` 只解决 Stage 0，不保存 Core/Full 业务步骤列表。进入 PowerShell 后立即把控制权交给根 `install.ps1`。

## 编号与文件

| 编号 | 逻辑 ID | macOS 目标文件 | 所有者 |
|---|---|---|---|
| `00` | `bootstrap` | `macos/00bootstrap.zsh` | macOS + 根编排接口 |
| `01` | `package-manager` | `macos/01installHomebrew.zsh` | macOS |
| `02` | `pwsh` | `macos/02installPowerShell.zsh` | macOS；安装命令可由 Stage 0 helper 包装 |
| `03` | `sources` | `macos/03configureSources.zsh` | 网络源任务提供核心 adapter，macOS 只包装 |
| `04` | `shell` | `macos/04deployShellConfig.zsh` | 复用 `shell/deploy.sh` |
| `05` | `core-cli` | `macos/05installCoreCli.ps1` | 复用应用清单和 psutils |
| `06` | `fonts` | `macos/06installFonts.ps1` | 复用字体安装能力 |
| `07` | `profile-tools` | `macos/07installProfileTools.ps1` | 复用 Profile、模块、bin 和构建入口 |
| `08` | `full-apps` | `macos/08installFullApps.ps1` | 复用应用清单和 psutils |
| `09` | `platform-automation` | `macos/09deployHammerspoon.zsh` | 复用 Hammerspoon loader |
| `10` | `login-items` | `macos/10configureLoginItems.zsh` | macOS |
| `11` | `desktop-integration` | `macos/11installQuickActions.zsh` | macOS |
| `99` | `verify` | `macos/99verifyInstall.zsh` | macOS，只读 |

旧 `01`～`08` 文件一次性重命名并更新所有仓内引用，不保留长期兼容 shim。相关 `.trellis/spec/infra/*.md` 中的旧文件名在实现完成后同步更新。

## 公共叶子契约

### 参数

- zsh 变更脚本：至少支持 `-h|--help` 和 `--dry-run`；未知参数返回 2。
- PowerShell 变更脚本：使用 `[CmdletBinding(SupportsShouldProcess)]`，通过 `-WhatIf` 预览。
- 可撤销步骤提供 `--uninstall`、`--remove` 或等价显式参数，不把回滚隐藏在重复执行中。
- 叶子脚本只接收自身参数；Core/Full 和步骤图由根编排器解释。

### 退出状态

| 退出码 | 含义 |
|---|---|
| `0` | 成功、已满足或明确跳过 |
| `1` | 执行失败或验证失败 |
| `2` | 参数错误 |
| `10` | `Blocked`：缺少权限、交互前置或上游能力，重试前需要外部动作 |

根编排器映射为 `Succeeded`、`Skipped`、`Failed`、`Blocked`，并记录步骤 ID、耗时、退出码和错误摘要。叶子脚本不能吞掉失败后仍返回 0。

### 日志与预览

- stdout 输出正常步骤日志，stderr 输出警告和错误。
- `--dry-run`/`-WhatIf` 不写文件、不安装包、不启动 GUI、不读取会触发 GUI/Automation 的应用路径。
- 严格非交互模式禁止等待 stdin、sudo、AppleScript 或 GUI 权限弹窗；不能继续时返回 10。

## Stage 0

### 启动方式

`00bootstrap.zsh` 支持两种来源：

- 仓库内运行：直接使用当前仓库根目录。
- 远程最小入口：脚本先完成系统预检与 Git 前置，再 clone 到 `--repo-dir`，随后执行仓库内同一入口的 resume 路径。远程入口不携带应用清单；PowerShell 7 可用后立即移交根 Stage 1，由根编排器执行 `03 sources`。

默认仓库地址沿用当前官方 GitHub 地址，允许 `--repo-url` 与 `--repo-dir` 覆盖。国内网络的 repo/bootstrap 例外由网络源任务集中定义，不在脚本散落镜像 URL。

### 交互等级

- 默认：允许 Homebrew、sudo、CLT fallback 和系统权限提示。
- `--unattended`：启动时允许一次 `sudo -v`，随后使用非交互命令；隐藏提示视为 Blocked。
- `--non-interactive`：首先验证 `sudo -n true` 与全部系统前置，不满足立即返回 10；面向 MDM/CI/已预置机器。

从 Setup Assistant 开始的零接触部署与 MDM/PPPC 控制面不在范围内。

## 应用清单与标签

`profile/installer/apps-config.json` 是唯一软件真源，继续使用现有 `tag` 数组：

- 场景：`macbook`、`linuxserver`。
- 预设：`core`、`full`。
- 类别：`cli`、`font`、`gui`、`platform`。
- 可选组：`terminal-extras`、`ai-cli`。

选择规则：

- Core 选择 `core`；Full 选择 `core OR full`。
- `05` 选择 `core AND cli`。
- `06` 选择 `core AND font`。
- `08` 选择 `full AND (gui OR platform)`。
- 无 `core/full` 的 `terminal-extras`、`ai-cli` 只允许显式组或单项安装。
- `skipInstall: true` 始终优先。

首期 Core CLI：`fnm`、`jq`、`fd`、`eza`、`ripgrep`、`fzf`、`zoxide`、`starship`、`bat`、`uv`。

新增配置校验覆盖：保留标签拼写、`core/full` 冲突、预设项缺少或拥有多个类别、Core CLI 清单可解析。标签选择逻辑放在 psutils 的安装领域函数中，macOS/Linux/Windows 叶子脚本复用，不各写一套过滤器。

## 包安装结果契约

现有 `Install-PackageManagerApps` 会捕获单项错误后继续，且没有结构化返回。修改为：

1. 先由纯选择函数根据 OS、required/any/excluded tags 与 `skipInstall` 生成候选项。
2. 对所有候选逐项尝试，返回对象数组：`Name`、`PackageManager`、`Status`、`ExitCode`、`Message`。
3. 状态至少包含 `Installed`、`AlreadyPresent`、`Skipped`、`Preview`、`Failed`。
4. 单项失败不阻止同一步骤的其他包，步骤结束后只要 required item 有失败就以退出码 1 结束。
5. 原 `ConfigPath` 与 `ConfigObject` 调用保持兼容；新叶子脚本通过共享 config resolver 加载 JSON 后传 `ConfigObject`，避免新增 ad hoc parser。

## 各步骤设计

### 01 Homebrew

- 严格模式、macOS/curl/架构前检、help 和 dry-run。
- 已安装时恢复 `/opt/homebrew` 或 `/usr/local` 的 `brew shellenv`。
- 安装时按交互等级设置 `NONINTERACTIVE=1`；安装后立即在当前进程加载 shellenv。
- 验证 `brew --prefix` 与可执行性。镜像配置不属于本脚本。

### 02 PowerShell

- 先恢复 Homebrew PATH，再检测 `pwsh` 主版本。
- 不满足 PowerShell 7 基线时执行 `brew install --cask powershell` 或升级。
- China/Auto 可由 POSIX Stage 0 helper 为该安装命令临时注入 Homebrew 镜像变量。
- 支持 dry-run，安装后以 `pwsh -NoProfile` 验证。

### 03 Sources

- `Direct` 为可观察的成功 no-op；`China`/`Auto` 委托网络源 adapter。
- adapter 缺失时 Direct 可继续，China/Auto 返回 Blocked，防止静默使用错误源。
- 本脚本不保存镜像 URL，也不直接追加 `~/.zshrc`。

### 04 Shell

- 只调用 `shell/deploy.sh --shell zsh` 并透传 dry-run/exclude。
- 不修改仓库文件执行位；缺少目标脚本返回 1。
- `shell/deploy.sh` 修改现有 `.zshrc`/`.bashrc` 前先按时间戳备份，只在 loader 缺失时写入。

### 05 Core CLI

- 通过共享 config resolver 加载 `apps-config.json`。
- 验证标签后选择 `macOS + core + cli`，调用结构化包安装函数。
- 安装 fnm 后不在本步骤隐式安装全部 Node 工具；Node runtime 准备属于 `07`。

### 06 Fonts

- 从同一清单选择 `macOS + core + font`。
- 复用字体安装能力，单次读取已安装 cask 列表，支持 WhatIf 与结果汇总。
- 验证字体 cask 或用户字体目录中的实际安装结果。

### 07 Profile、模块与仓库工具

按顺序调用既有能力：

1. 安装 macOS 适用 PowerShell 模块：Pester、PSReadLine；BurntToast 只保留 Windows。
2. 运行 `profile/profile.ps1 -LoadProfile`；仅在目标内容变化时备份并写 `$PROFILE`。
3. 通过 fnm 获得约定 Node LTS，并按根 `packageManager` 字段准备 pnpm。
4. `Manage-BinScripts.ps1 -Action sync -Force`。
5. `scripts/bash/build.sh`。
6. 安装并构建 `scripts/node`。
7. 通过 uv 安装或运行 nbstripout，替代不确定的裸 `pip install`。

每个子组件独立汇总；失败导致步骤 1，但清晰显示已完成部分。Nix devshell 的 Node/Rust 工具链不由此步骤自动选择。

### 08 Full Apps

- 从同一清单选择 `macOS + full + gui/platform`。
- 保留当前已激活的 macbook GUI 行为；未标 Full 或 `skipInstall` 的 Docker Desktop、DockDoor、Ice 等不自动加入。
- `blueutil` 作为 Full platform dependency，先于 Hammerspoon 部署验证。

### 09 Hammerspoon

- 保持 loader 与 manifest 真源。
- 复制前比较文件内容；相同文件不备份、不重写。
- 只在内容变化时生成时间戳 `.bak`，保留 `config.local.lua`。
- dry-run 不安装/启动 GUI；`--no-launch` 保留。

### 10 Login Items

- dry-run 只列出声明项，不通过 AppleScript 解析应用。
- 真实模式优先固定应用路径；动态查询必须有边界并在失败时返回 Blocked。
- 支持移除本脚本管理的登录项，逐项汇总。

### 11 Quick Actions

- 源 workflow 先通过 plutil 验证。
- 已安装目标在覆盖前创建时间戳备份；在临时目录配置并验证后再替换。
- 用声明数组/manifest 管理 workflow，或在只有一个条目时使用准确的单项文案。
- 保持现有 runner/action 分层和 uninstall。

### 99 Verify

- 保持只读，支持 `--step`、`--preset Core|Full`，并为根编排器提供结构化输出选项。
- Core 覆盖 repo、brew、sources、pwsh、shell、10 个 Core CLI、3 个字体、Profile、模块、bin 与仓库工具。
- Full 追加应用、Hammerspoon manifest、登录项与 Quick Actions。
- PowerShell 可用后从 `apps-config.json` 动态读取期望项；pwsh 缺失时先记录该步骤失败，再跳过依赖 catalog 的检查，不维护硬编码包列表。
- WARN 不改变退出码，preset required failure 返回 1，读取系统权限失败可报告 Blocked/不可验证状态。

## 失败、重跑与依赖

- 包安装步骤内部尝试所有候选后汇总；跨步骤由根编排器根据依赖停止或标记 Blocked。
- 无论前序失败，根编排器最后应允许运行可执行的 verify 子集。
- 重跑叶子步骤必须幂等，不因已有安装或相同配置制造额外备份。

## 兼容与实施依赖

本设计先作为下游任务输入。代码实施顺序为：

1. 网络源任务实现 `02` 所需 adapter。
2. 统一编排器实现步骤注册与 Stage 1 接口。
3. 回到本任务实施全部 macOS 叶子脚本与 `00` 移交。

这样避免在 `00` 或 `02` 中引入临时串联逻辑。

## 安全与回滚

- 不保存管理员密码，不写 `NOPASSWD: ALL`，不绕过 TCC/SIP/Gatekeeper。
- 修改用户配置前按可读时间戳生成 `.bak`；未变化不备份。
- source 恢复由网络源任务负责；Quick Actions、登录项提供显式卸载；Hammerspoon 保留本机覆盖和备份。
- 文件重命名可通过 Git 恢复，仓外调用方不承诺兼容。
