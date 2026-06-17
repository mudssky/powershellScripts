# Hammerspoon 合盖休眠保护

## Goal

为 `macos/hammerspoon` 增加面向 MacBook 电池合盖场景的休眠保护配置：在笔记本合盖且使用电池时，自动处理会阻止休眠或反复唤醒设备的因素，例如退出空闲的 RustDesk、断开或关闭蓝牙连接，从而降低合盖后的耗电和异常唤醒概率。

用户价值：

- 合盖放包或离开时，不再因为远控应用、蓝牙设备连接或蓝牙被重新拉起导致持续耗电。
- Hammerspoon 配置从单一 `win.lua` 演进为可扩展的功能目录，后续可以继续添加电源、设备、应用守护类自动化。
- 默认行为保持可控：只在明确的笔记本电池合盖条件下执行高影响操作，并通过本机配置覆盖风险项。

## Confirmed Facts

- 现有 Hammerspoon 目录为 `macos/hammerspoon/`，包含 `config.lua`、`config.local.example.lua`、`init/init.lua`、`win.lua`、`load_scripts.zsh` 和 README。
- 现有 `init/init.lua` 固定加载 `scripts/win.lua`，并通过 `_G.HammerspoonConfig` 向功能脚本传入仓库默认配置与本机覆盖配置。
- 现有 `config.lua` 已有 `enabledGroups`，默认启用 `reload`、`window`、`launcher`，默认关闭高冲突功能组。
- 现有 `load_scripts.zsh` 只把 `macos/hammerspoon` 根层的 `*.lua` 复制到 `~/.hammerspoon/scripts/`，不会递归复制未来子目录。
- 现有 `macos/06verifyInstall.zsh --step hammerspoon` 只检查 `init.lua`、`config.lua`、`config.local.lua`、`scripts/win.lua` 和 manifest 中的对应条目。
- 归档任务 `06-16-hammerspoon-config-audit` 已决策：Hammerspoon 配置采用“启动器 + 默认配置/本机覆盖 + 功能脚本”的三层结构，默认保持低冲突，不自动修改本机 `~/.hammerspoon`，部署验证优先使用 dry-run。
- Context7 Hammerspoon 文档确认 `hs.caffeinate.watcher.new(...):start()`、`hs.execute()`、`hs.pathwatcher`、`hs.caffeinate.currentAssertions` 都属于 Hammerspoon 官方文档覆盖的能力。
- Context7 blueutil 文档确认 `blueutil --power` 可读取蓝牙电源状态，`blueutil --power 0` / `blueutil --power off` 可关闭蓝牙，`blueutil --power on` 可开启蓝牙。
- 用户提供的 RustDesk 示例已经包含可复用的业务条件：合盖、电池供电、RustDesk 正在运行、TCP established 连接数为 0、连续多次空闲后退出。
- 当前仓库未发现 `blueutil` 配置或蓝牙断连工具封装。
- 用户已确认把 `blueutil` 加入 `profile/installer/apps-config.json` 的 macbook 安装集合，作为 Hammerspoon 合盖休眠保护的显式依赖。
- 用户先前确认合盖休眠保护可保持仓库默认关闭；后续要求“直接都启动”“合盖门禁也启动”，当前仓库默认配置已显式启用 `power-lid-sleep` 和蓝牙守卫。
- 用户希望 Hammerspoon 后续采用插件化模式，配置跟随各插件组织，避免所有功能共享一个庞大的全局配置表。
- 用户明确指出该功能在 Mac mini 上不应该生效。
- 当前机器 `sysctl -n hw.model` 输出类似 `Mac17,3`，不能仅靠型号字符串前缀判断是否 MacBook；插件需要采用更稳的 laptop/clamshell 能力检测。
- 用户已确认插件契约采用“目录即插件 + 每个插件一个 `plugin.lua` 元数据/入口文件”。
- 用户已确认本任务一次性完成插件化迁移：现有 `win.lua` 也迁移为 `plugins/win-hotkeys/plugin.lua`，不保留旧脚本形态作为长期入口。

## Requirements

- 新增合盖休眠保护插件，默认应能通过 `config.lua` 和 `config.local.lua` 控制启用状态。
- Hammerspoon 功能应支持插件化扩展：每个插件拥有自己的默认配置、启动入口和本机覆盖配置命名空间。
- 插件配置应按插件名分组，避免所有功能配置堆叠在全局 `enabledGroups` 和根层字段中。
- 插件目录契约采用 `plugins/<plugin-id>/plugin.lua`；插件私有模块放在同目录下。
- 现有快捷键功能需要迁移为 `win-hotkeys` 插件；原有默认功能组、快捷键配置、`modifierSwap`、`taskbarApps` 等语义保持兼容。
- 迁移后 `init.lua` 只通过插件加载器启动 Hammerspoon 功能，不再直接加载根层 `win.lua`。
- 合盖休眠插件必须做 MacBook/laptop 硬件门禁；在 Mac mini 等没有合盖语义的设备上，即使用户误开启配置，也不得执行退出应用或关闭蓝牙等高影响动作。
- 硬件门禁首选检测 `AppleClamshellState` 是否可读；读不到合盖状态时默认视为不支持，并跳过插件动作。
- 休眠保护只应在笔记本合盖且电池供电时执行高影响动作；接通电源或开盖时应重置空闲计数。
- RustDesk 首版策略：
  - 检测 RustDesk 是否运行。
  - 检测 RustDesk 是否存在 TCP established 连接。
  - 当合盖、电池供电、RustDesk 运行且连续多次无活动连接时，退出 RustDesk。
  - 有活动连接时不退出，避免中断真实远程会话。
- 蓝牙首版策略采用强策略：仅在“电池供电 + 合盖 + 功能显式启用”时关闭蓝牙电源，开盖或唤醒后恢复之前状态，并在合盖期间周期性检查以应对蓝牙被重新拉起。
- 首版不加入外接显示器检测；触发条件保持为“电池供电 + 合盖”，避免引入额外硬件状态依赖。
- 功能应通过 timer、caffeinate watcher、battery watcher 等多触发源检查，而不是只依赖单一周期轮询。
- 功能脚本要可扩展，避免把电源、蓝牙、应用策略继续堆进 `win.lua` 或单一 `power.lua`。
- 部署脚本需要支持未来目录结构：如果新增子目录或模块文件，必须能复制到 `~/.hammerspoon/scripts/` 并写入 manifest，避免本机缺文件。
- 验证脚本和 README 需要同步新增托管文件、配置项和使用边界。
- `blueutil` 需要加入 `profile/installer/apps-config.json`：`brew install blueutil`、`supportOs: ["macOS"]`、`tag: ["macbook"]`。
- 即使 `blueutil` 缺失，RustDesk 保护逻辑仍应可运行；蓝牙保护应记录日志或提示后跳过。

## Acceptance Criteria

- [ ] `prd.md` 记录合盖休眠保护的目标、已确认事实、需求、验收标准和仍需用户拍板的风险决策。
- [ ] `design.md` 给出可扩展目录结构、配置结构、运行时流程、蓝牙策略边界和部署/验证影响。
- [ ] `implement.md` 给出实施顺序、验证命令、风险文件和回滚点。
- [ ] 若进入实现，现有 `win.lua` 快捷键行为迁移到 `plugins/win-hotkeys/plugin.lua` 后，默认启用范围和本机覆盖配置语义保持兼容。
- [ ] 若进入实现，默认配置即使启用合盖休眠保护，也必须在未满足合盖门禁、电池供电和合盖状态时不退出应用或修改蓝牙状态。
- [ ] 若进入实现，Mac mini 等非笔记本设备上即使误开启插件，也不会退出 RustDesk 或修改蓝牙状态。
- [ ] 若进入实现，RustDesk 有活动 TCP 连接时不会被退出；无活动连接需要连续达到阈值才退出。
- [ ] 若进入实现，合盖休眠保护只在电池供电且合盖时执行退出应用和蓝牙动作。
- [ ] 若进入实现，部署 dry-run 能展示新增脚本或模块会被复制并进入 manifest。
- [ ] 若进入实现，`macos/06verifyInstall.zsh --step hammerspoon` 与 README 反映新增托管文件或明确只验证基础部署。
- [ ] 若进入实现，执行根目录 `pnpm qa`；如涉及 pwsh 验证脚本改动，提交前执行 `pnpm test:pwsh:all` 或说明 Docker/环境限制。

## Likely Out Of Scope

- 不实现通用 GUI 配置界面。
- 不在 Hammerspoon 脚本里自动安装 Homebrew 依赖。
- 不强制部署或修改当前机器的 `~/.hammerspoon`，除非用户后续明确要求。
- 不做完整电源策略管理器；首版聚焦电池合盖后的休眠阻塞与蓝牙唤醒问题。
- 不中断 RustDesk 正在进行的远程连接。

## Open Questions

- 无阻塞问题；规划已可进入实现前评审。

## Notes

- Context7 library query selected `/hammerspoon/hammerspoon.github.io` as official Hammerspoon documentation source.
- Context7 docs confirmed `hs.caffeinate`、`hs.caffeinate.watcher`、`hs.execute` and `hs.pathwatcher` are documented Hammerspoon capabilities.
- Context7 library query selected `/toy/blueutil` for macOS Bluetooth CLI documentation.
