# 优化 Hammerspoon 配置

## Goal

审计并规划 `macos/hammerspoon` 配置的优化与瘦身方向，让本仓库的 Hammerspoon 配置在当前 macOS 上更稳定、低冲突、易部署，并保留真正有使用价值的 Windows 风格快捷键。

用户价值：

- 减少全局快捷键误触、重复绑定和与 macOS 原生快捷键的冲突。
- 修复当前配置中会导致部分快捷键运行时报错或无效的实现问题。
- 明确哪些功能应保留、默认关闭、迁移到可选配置，或删除。

## Confirmed Facts

- 目标目录包含 4 个文件：`macos/hammerspoon/README.md`、`macos/hammerspoon/init/init.lua`、`macos/hammerspoon/load_scripts.zsh`、`macos/hammerspoon/win.lua`。
- `macos/05deployHammerspoon.sh` 会调用 `macos/hammerspoon/load_scripts.zsh`，`macos/INSTALL.md` 将其列为 macOS 安装流水线第 5 步。
- 用户已选择默认目标为“精简稳定的 macOS 工作流增强”，不是完整复刻 Windows 快捷键。
- `win.lua` 以“Windows 风格快捷键”为目标，绑定范围很宽，包含窗口管理、窗口排列、文本编辑、浏览器、系统、截图、音量、虚拟桌面、应用快速启动和 Finder 文件操作。
- `win.lua` 默认启用 `HAMMERSPOON_MODIFIER_SWAP=true` 语义：`win` 绑定为 macOS `ctrl`，`ctrl` 绑定为 macOS `cmd`。
- 默认交换模式会让 README 中写的 `Win+方向键` 实际绑定到 `Ctrl+方向键`，让 `Ctrl+C/V/X/Z` 实际绑定到 `Cmd+C/V/X/Z`；这更像“把文档标签重解释为 Mac 物理键”，而不是保持 Windows 物理肌肉记忆。
- `launchOrFocusApp` 在 `win.lua` 后半段才用 `local function` 定义，但前面的 `Win+E`、`Win+X`、`Ctrl+Shift+Esc`、`Win+I`、`Win+F12` 已闭包引用它；Lua 中这种写法不会让前面的闭包捕获后声明的 local，按下这些快捷键时存在调用 nil 全局的风险。
- 当前本机是 macOS 26.5.1，存在 `/System/Applications/System Settings.app`，未发现旧的 `System Preferences.app`；`win.lua` 和 README 仍使用 `System Preferences`。
- 当前本机未发现 `/Applications/Hammerspoon.app`、`~/Applications/Hammerspoon.app` 或 Homebrew cask 安装记录；`load_scripts.zsh` 只检查 `/Applications/Hammerspoon.app`，检测路径过窄。
- `init/init.lua` 会同时扫描 `~/.hammerspoon` 与 `~/.hammerspoon/scripts` 下所有 `.lua` 文件，目录扫描加载顺序未排序，后续新增脚本时顺序不可预测。
- `init/init.lua` 配置了 reload 快捷键和 `.lua` 文件变更监听。Context7 官方 Hammerspoon 文档确认 `hs.hotkey.bind`、窗口半屏、`hs.pathwatcher` reload 都是常规用法，且 `hs.reload()` 会重建 Lua 解释器。
- `load_scripts.zsh` 每次部署都会覆盖 `~/.hammerspoon/init.lua` 并备份，但只复制仓库根层 `*.lua` 到 `~/.hammerspoon/scripts`，不会清理已删除的旧脚本。
- README 中 `brew install hammerspoon` 与安装配置里的 `brew install --cask hammerspoon` 不一致；现代 Homebrew 安装 Hammerspoon 应使用 cask。
- `profile/installer/apps-config.json` 中 Hammerspoon 只有 `supportOs: ["macOS"]`，没有 `tag: ["macbook"]`；而 `macos/04installApps.ps1` 只安装 tag 包含 `macbook` 的 Homebrew 项，所以当前 macOS 安装流水线第 4 步不会安装 Hammerspoon，第 5 步却要求它已安装。
- README 推荐通过 `~/.zshrc` / `~/.bash_profile` 设置 `HAMMERSPOON_MODIFIER_SWAP`；但 Hammerspoon 通常作为 GUI app 启动，不能稳定依赖交互 shell rc 注入环境变量。
- 用户已确认配置文件采用“仓库提交默认配置 + 本机 local 覆盖”的方案。
- 用户已确认精简默认核心范围：窗口吸附、锁屏、Finder、Spotlight/System Settings、配置 reload；`Alt+Tab` 单独作为可选开关，默认关闭或不并入核心组。
- 用户确认窗口吸附当前没有明显冲突，可以先作为默认核心功能保留。

## Requirements

- 保留 Hammerspoon 配置的主要目标：提供少量高价值、可预测的 Windows 风格快捷键，而不是全量模拟 Windows。
- 修复 `launchOrFocusApp` 局部函数声明顺序导致的运行时风险。
- 修复或兼容现代 macOS 应用名称：优先使用 `System Settings`，保留旧系统兼容映射。
- 收窄或模块化高冲突快捷键，尤其是会覆盖 macOS 原生行为或应用内常用快捷键的全局绑定。
- 配置入口应以仓库默认 Lua 配置 + 本机 local Lua 覆盖为主，环境变量只作为兼容兜底；默认配置应明确表达启用哪些功能组。
- 明确 `HAMMERSPOON_MODIFIER_SWAP` 的默认策略，并让 README、控制台输出、脚本行为一致；精简默认下应优先考虑关闭交换或重命名语义，减少“文档写 Win 实际按 Ctrl”的认知错位。
- 改善部署脚本的可验证性：安装检测不能只依赖 `/Applications/Hammerspoon.app`；部署应避免遗留已删除脚本导致幽灵配置。
- 修正 macOS 安装流水线：Hammerspoon 要么纳入 `macbook` 安装集合，要么部署脚本提供明确的安装提示/可选自动安装，不能让第 4 步跳过、第 5 步失败。
- README 应从“功能全集”改为与实际默认启用范围一致，并说明可选功能如何开启。
- 精简默认只启用低冲突核心组：窗口吸附、锁屏、Finder、Spotlight/System Settings、配置 reload。窗口吸附默认保留；文本编辑、浏览器标签、Finder 删除/重命名、虚拟桌面创建/关闭、`Win+1..9`、F13 截图默认关闭；`Alt+Tab` 单独可配置。

## Candidate Optimizations

- 将 `launchOrFocusApp` 提前到首次使用之前，或改为 `local launchOrFocusApp` 前置声明后赋值。
- 将快捷键分组配置化，例如 `window`、`text`、`browser`、`system`、`screenshot`、`volume`、`spaces`、`apps`、`finder`，默认只启用低冲突核心组。
- 默认功能组建议拆为 `window`、`launcher`、`reload` 等核心组，以及 `altTab`、`text`、`browser`、`finderActions`、`spaces`、`apps`、`screenshot` 等可选组。
- 新增仓库默认配置和本机覆盖入口，例如 `config.lua` + `config.local.lua`：前者提交默认行为，后者加入 `.gitignore` 并由部署脚本保留/生成；配置承载 `modifierSwap`、`enabledGroups`、`taskbarApps`、提示开关等，`win.lua` 只读取配置，不要求用户改主逻辑文件。
- 在 `init/init.lua` 中先加载配置，再加载功能脚本；保留 `_G.modifierSwapped` 与环境变量作为旧配置兼容路径。
- 将 `System Preferences` 改为兼容映射：新系统使用 `System Settings`，旧系统保留 `System Preferences`。
- 将 `load_scripts.zsh` 的 Hammerspoon 检测改为 `open -Ra Hammerspoon`、`mdfind` 或多路径检测，而不是单一路径。
- 部署时同步 `scripts` 目录，或只部署明确清单中的脚本，避免已经从仓库删除的 Lua 文件继续留在 `~/.hammerspoon/scripts`。
- 部署脚本支持 `--dry-run`、`--no-launch`、`--install` 或至少输出 `brew install --cask hammerspoon`，让安装和部署边界清楚。
- 部署前为将被覆盖的本机配置创建可读时间戳 `.bak`；本地私有配置文件若存在，不应覆盖。
- `profile/installer/apps-config.json` 给 Hammerspoon 补 `macbook` tag，或调整 macOS app 安装筛选策略，保证 `macos/INSTALL.md` 的第 4 步和第 5 步闭环。
- `init/init.lua` 加载脚本前排序，或改为显式加载清单，避免后续多脚本时顺序漂移。
- 减少启动时多次 `hs.alert.show`：当前 `init/init.lua` 和 `win.lua` 都会弹加载提示，长期使用会偏吵。
- 将 `taskbarApps` 变成用户可覆盖配置，而不是固定 Safari、Terminal、VS Code 等应用。
- 为窗口吸附增加多显示器/边距处理时保持现有简单半屏逻辑，不引入重型窗口管理框架。

## Likely Redundant Or Risky Defaults

- 文本编辑全局映射 `Ctrl+A/C/V/X/Z/S/F/N/O/P/W/T`：默认交换模式下多为 macOS 原生 `Cmd+...` 的重复绑定；标准模式下才更像 Windows 物理快捷键迁移。
- 浏览器全局映射 `Ctrl+Tab`、`Ctrl+Shift+Tab`、`Ctrl+R`、`Ctrl+Shift+T`：只对浏览器/标签应用自然，全局绑定可能影响编辑器、终端、IDE。
- Finder 文件操作全局映射 `F2`、`Delete`、`Shift+Delete`、`Ctrl+Shift+N`：不限制前台应用时容易误伤非 Finder 应用。
- 虚拟桌面创建/关闭通过 Mission Control 后延迟发送 `return` / `delete`：依赖 UI 状态和延迟，稳定性弱，默认启用风险高。
- `Win+1` 到 `Win+9` 固定应用列表：强个人化且与每台机器实际 Dock/常用应用不一定一致，适合作为可选本地覆盖。
- `Win+X` 与 `Win+I` 都打开系统设置，功能重复。
- `F13` 作为 Print Screen 兼容键只对特定键盘有意义，可作为可选组。
- `Alt+Tab` 触发 `Cmd+Tab` 可能有价值，但全局截获 `Alt+Tab` 会改变 macOS Option+Tab 在部分应用内的语义，需要确认是否作为核心保留。
- `Alt+Tab` 已决策为可选开关，不并入默认核心组。

## Acceptance Criteria

- [x] PRD 记录当前 Hammerspoon 配置中已确认的问题、可优化点、可能冗余项和下一步范围决策。
- [x] 用户明确默认策略：采用精简稳定默认，减少全局快捷键冲突。
- [x] 用户明确精简默认核心范围：窗口吸附、锁屏、Finder、Spotlight/System Settings、配置 reload；`Alt+Tab` 可选。
- [x] 若进入实现，`win.lua` 中应用启动快捷键不再因 `launchOrFocusApp` 声明顺序失败。
- [x] 若进入实现，现代 macOS 上系统设置快捷键可启动 `System Settings`。
- [x] 若进入实现，配置入口不再依赖 GUI Hammerspoon 读取 shell rc 环境变量；仓库默认 Lua 配置 + 本机 local 覆盖可控制功能组。
- [x] 若进入实现，README 与默认启用的快捷键范围一致。
- [x] 若进入实现，部署脚本能在 Hammerspoon 安装路径不在 `/Applications/Hammerspoon.app` 时给出正确判断或提示。
- [x] 若进入实现，macOS 安装流水线能安装 Hammerspoon 或明确跳过原因，不出现第 4 步跳过、第 5 步失败的断点。
- [x] 若进入实现，执行根目录 `pnpm qa`；如果只改文档则可跳过。

## Out Of Scope

- 本轮不设计完整窗口管理器替代品。
- 本轮不处理 Karabiner-Elements 级别的物理按键重映射。
- 本轮不新增 GUI 配置界面。
- 本轮不自动修改本机 `~/.hammerspoon`，除非用户后续明确要求部署。

## Open Questions

- 无阻塞问题；规划已可进入实现设计。

## Evidence Notes

- Context7 library query selected `/hammerspoon/hammerspoon.github.io` as official Hammerspoon documentation source.
- Context7 docs confirmed reload hotkey、窗口半屏和 `hs.pathwatcher` reload 属于官方示例覆盖的常规用法。
