# Hammerspoon 合盖休眠保护设计

## Architecture

沿用现有三层结构，但把功能脚本统一演进为插件目录。合盖休眠保护作为新插件落地，现有快捷键脚本也迁移为 `win-hotkeys` 插件：

```text
macos/hammerspoon/
├── config.lua
├── config.local.example.lua
├── init/
│   └── init.lua
├── plugins/
│   ├── power-lid-sleep/
│   │   ├── plugin.lua
│   │   ├── app_guard.lua
│   │   ├── bluetooth_guard.lua
│   │   └── lid_state.lua
│   └── win-hotkeys/
│       └── plugin.lua
├── load_scripts.zsh
└── README.md
```

部署后：

```text
~/.hammerspoon/
├── init.lua
├── config.lua
├── config.local.lua
├── .powershellscripts-hammerspoon.manifest
└── scripts/
    └── plugins/
        ├── power-lid-sleep/
        │   ├── plugin.lua
        │   ├── app_guard.lua
        │   ├── bluetooth_guard.lua
        │   └── lid_state.lua
        └── win-hotkeys/
            └── plugin.lua
```

设计取舍：

- `win.lua` 迁移为 `plugins/win-hotkeys/plugin.lua`，本任务完成后功能入口统一走插件加载器。
- `plugins/win-hotkeys/plugin.lua` 承接现有快捷键逻辑，保持默认功能组、快捷键配置、应用列表和兼容环境变量语义。
- `plugins/power-lid-sleep/plugin.lua` 作为插件入口，负责提供默认配置、合并本机覆盖、启动 watcher。
- `plugins/power-lid-sleep/*.lua` 拆分合盖状态、应用退出策略、蓝牙策略。
- `load_scripts.zsh` 从只复制根层 `*.lua` 升级为复制托管插件目录，并把所有托管 Lua 文件写入 manifest。

## Plugin Contract

插件目录契约：

```text
plugins/<plugin-id>/
├── plugin.lua      # 返回插件表
└── *.lua           # 插件私有模块
```

`plugin.lua` 返回表：

```lua
return {
	id = "power-lid-sleep",
	defaultConfig = {
		enabled = false,
	},
	start = function(context)
		-- 读取 context.config，注册 watcher。
	end,
}
```

插件自身的 `defaultConfig.enabled = false` 是缺少仓库配置时的安全兜底；仓库 `config.lua` 可按本机需求显式启用插件。

`init.lua` 负责：

- 读取仓库默认配置和本机覆盖配置。
- 按显式插件清单加载插件，首版清单包含 `win-hotkeys` 和 `power-lid-sleep`。
- 将 `HammerspoonConfig.plugins[plugin.id]` 与 `plugin.defaultConfig` 合并后传入 `plugin.start(context)`。
- 记录插件加载成功/失败数量。

这个契约让配置跟随插件组织，同时保留显式清单，避免目录扫描顺序和隐藏文件带来的不可预测行为。

## Configuration

仓库默认配置新增：

```lua
plugins = {
	["win-hotkeys"] = {
		enabled = true,
		enabledGroups = {
			reload = true,
			window = true,
			launcher = true,
			altTab = false,
			text = false,
			browser = false,
			system = false,
			screenshot = false,
			volume = false,
			spaces = false,
			apps = false,
			finderActions = false,
		},
	},
	["power-lid-sleep"] = {
		enabled = true,
		requireClamshell = true,
		unsupportedDevicePolicy = "skip",
		checkIntervalSeconds = 15,
		requiredIdleChecks = 4,
		onlyOnBattery = true,
		apps = {
			{
				name = "RustDesk",
				quitWhenIdle = true,
				idleConnectionCommand = [[lsof -nP -a -c RustDesk -iTCP -sTCP:ESTABLISHED 2>/dev/null | awk 'NR > 1 {count++} END {print count + 0}']],
			},
		},
		bluetooth = {
			enabled = true,
			mode = "powerOff",
			restoreOnWake = true,
			enforceWhileLidClosed = true,
		},
	},
}
```

`win-hotkeys` 默认启用，保持现有快捷键行为。用户已要求“直接都启动”，所以仓库 `config.lua` 默认启用 `power-lid-sleep` 和蓝牙守卫；安全边界由 `requireClamshell`、`onlyOnBattery` 和合盖状态共同保证。用户可在 `config.local.lua` 中关闭该插件或关闭蓝牙守卫。

为兼容现有本机覆盖配置，首版加载器应把旧配置字段桥接到插件配置：

- 根层 `modifierSwap`、`showAlerts`、`hotkeys`、`taskbarApps` 继续供 `win-hotkeys` 读取。
- 根层 `enabledGroups` 继续作为 `win-hotkeys.enabledGroups` 的兼容来源。
- 新配置优先使用 `plugins["win-hotkeys"]` 和 `plugins["power-lid-sleep"]`。

## Runtime Flow

```text
timer / battery watcher / caffeinate watcher
  -> read plugins["power-lid-sleep"] config
  -> check device supports clamshell state
  -> check onlyOnBattery and lidClosed
  -> app_guard checks RustDesk running + established connections
  -> bluetooth_guard applies configured bluetooth mode
  -> reset idle counters when conditions no longer match
```

合盖检测沿用用户示例里的 `ioreg -r -k AppleClamshellState -d 1`。电池状态使用 `hs.battery.powerSource()`。

RustDesk 策略沿用“连续空闲确认”而不是一次命中即退出，降低短暂网络状态误判风险。

## Device Gate

合盖休眠保护必须先确认当前设备支持合盖语义，Mac mini 上不应该生效。

设计门禁：

- 优先执行 `ioreg -r -k AppleClamshellState -d 1`。
- 能读取到 `AppleClamshellState` 时，认为设备支持合盖检测，再继续判断 Yes/No。
- 读不到该键时，认为是 Mac mini、Mac Studio、iMac 等非笔记本或不支持 clamshell 设备，插件只记录日志并跳过动作。
- `sysctl -n hw.model` 只用于日志诊断，不作为主判断条件，因为 Apple Silicon 型号码可能是 `Mac17,3` 这类不含产品线名称的字符串。

配置保留 `requireClamshell = true`，默认不允许关闭。若未来要支持特殊设备，可再追加明确的 allowlist，而不是首版开放任意覆盖。

## Bluetooth Strategy

首版采用强策略：电池合盖时关闭蓝牙电源，开盖或唤醒后按之前状态恢复；合盖期间可重复执行以防蓝牙被设备或系统重新拉起。

这个选择贴合用户已遇到的“合盖后蓝牙被重新开启”场景。仅断开设备的弱策略副作用更小，但需要维护设备地址，且设备可能很快重连，首版先不采用。

蓝牙控制首选 `blueutil --power`：

- `blueutil --power` 读取当前状态。
- `blueutil --power 0` 关闭蓝牙。
- `blueutil --power on` 恢复蓝牙。

`blueutil` 纳入 macbook 安装集合，安装命令为 `brew install blueutil`。运行时仍需要处理缺失情况：如果命令不可用，蓝牙保护跳过并写日志，RustDesk 保护继续执行。

首版不加入外接显示器检测；接通电源时已经不执行合盖休眠动作，电池合盖外接显示器的少数场景接受触发休眠保护。

## Compatibility

- 缺少外部蓝牙命令时，脚本应记录日志或提示，但不能影响 RustDesk 保护逻辑。
- 非笔记本设备读不到 `AppleClamshellState` 时必须跳过所有高影响动作。
- 接通电源时不执行合盖休眠动作，避免影响常见桌面模式或外接显示器 clamshell 使用。
- 有 RustDesk 活动连接时不退出应用。
- watcher 对象需要保存在模块级变量中，避免被 Lua 垃圾回收。

## Deployment And Verification

- `load_scripts.zsh` 需要递归复制 `plugins/**/*.lua` 并维护 manifest，同时清理上一轮托管的 `scripts/win.lua`。
- `profile/installer/apps-config.json` 需要新增 `blueutil`，并带 `supportOs: ["macOS"]` 与 `tag: ["macbook"]`。
- `macos/06verifyInstall.zsh --step hammerspoon` 需要从检查 `scripts/win.lua` 调整为检查 `scripts/plugins/win-hotkeys/plugin.lua` 与 `scripts/plugins/power-lid-sleep/plugin.lua`。
- 验证时优先执行：
  - `zsh -n macos/hammerspoon/load_scripts.zsh`
  - `zsh macos/hammerspoon/load_scripts.zsh --dry-run --no-launch`
  - `pnpm qa`
  - 若修改 `macos/06verifyInstall.zsh`，执行 `pnpm test:pwsh:all`

## Rollback

- 若 Hammerspoon 启动失败，回滚 `macos/hammerspoon/init/init.lua`、`plugins/*` 与 `config.lua`。
- 若部署 manifest 行为异常，回滚 `macos/hammerspoon/load_scripts.zsh`。
- 若验证脚本误报，回滚 `macos/06verifyInstall.zsh` 中新增的 hammerspoon 检查项。
