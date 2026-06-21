# Hammerspoon 插件配置

这个目录维护一套插件化的 macOS Hammerspoon 配置。默认启用 `win-hotkeys` 插件中的低冲突快捷键：窗口吸附、锁屏、Finder、Spotlight、系统设置和配置重载；其他 Windows 风格快捷键通过本机配置按需开启。仓库默认启用 `power-lid-sleep` 合盖休眠保护插件，用于在支持合盖状态的 MacBook、电池供电且合盖时退出空闲应用；蓝牙守卫默认关闭，按需通过本机配置开启。

## 默认快捷键

| 功能 | 快捷键 |
|------|--------|
| 窗口靠左半屏 | `Cmd+Alt+Ctrl+Left` |
| 窗口靠右半屏 | `Cmd+Alt+Ctrl+Right` |
| 窗口最大化 | `Cmd+Alt+Ctrl+Up` |
| 窗口最小化 | `Cmd+Alt+Ctrl+Down` |
| 锁定屏幕 | `Cmd+Alt+Ctrl+L` |
| 打开 Finder | `Cmd+Alt+Ctrl+E` |
| 打开 Spotlight | `Cmd+Alt+Ctrl+Space` |
| 打开 System Settings | `Cmd+Alt+Ctrl+I` |
| 重载 Hammerspoon 配置 | `Cmd+Alt+Ctrl+R` |
| 主动睡眠 | `Cmd+Ctrl+S` |

默认关闭的可选功能组包括：`altTab`、`text`、`browser`、`system`、`screenshot`、`volume`、`spaces`、`apps`、`finderActions`。

## 安装

1. 安装 Hammerspoon：

   ```zsh
   brew install --cask hammerspoon
   ```

2. 部署配置：

   ```zsh
   zsh macos/05deployHammerspoon.sh
   ```

部署脚本会复制 `init.lua`、默认配置和插件脚本到 `~/.hammerspoon/`，保留本机 `config.local.lua`，并启动或重启 Hammerspoon。

常用参数：

```zsh
zsh macos/05deployHammerspoon.sh --dry-run
zsh macos/05deployHammerspoon.sh --no-launch
zsh macos/05deployHammerspoon.sh --install
```

## 配置

仓库默认配置在 `config.lua`，部署后位于 `~/.hammerspoon/config.lua`。本机覆盖配置位于 `~/.hammerspoon/config.local.lua`，首次部署时会从 `config.local.example.lua` 生成，后续部署不会覆盖。

示例：

```lua
return {
	modifierSwap = false,
	showAlerts = false,
	enabledGroups = {
		altTab = true,
		volume = true,
	},
	plugins = {
		["win-hotkeys"] = {
			enabled = true,
			enabledGroups = {
				altTab = true,
				volume = true,
			},
		},
		["power-lid-sleep"] = {
			enabled = true,
			bluetooth = {
				enabled = false,
			},
		},
	},
	hotkeys = {
		windowModifiers = { "cmd", "alt", "ctrl" },
		launcherModifiers = { "cmd", "alt", "ctrl" },
	},
	taskbarApps = {
		"Finder",
		"Safari",
		"Terminal",
		"Visual Studio Code",
		"System Settings",
		"Activity Monitor",
		"Calculator",
		"TextEdit",
		"Preview",
	},
}
```

根层 `enabledGroups`、`modifierSwap`、`hotkeys` 和 `taskbarApps` 会继续作为 `win-hotkeys` 的兼容配置读取；新配置建议写在 `plugins["win-hotkeys"]` 和 `plugins["power-lid-sleep"]` 下。

### 插件

| 插件 | 默认 | 说明 |
|------|------|------|
| `win-hotkeys` | 开 | 低冲突核心快捷键和可选 Windows 风格快捷键组 |
| `power-lid-sleep` | 开 | MacBook 电池合盖时退出空闲应用；蓝牙守卫按需开启 |

### 功能组

| 组名 | 默认 | 说明 |
|------|------|------|
| `window` | 开 | 窗口半屏、最大化、最小化 |
| `launcher` | 开 | 锁屏、Finder、Spotlight、System Settings |
| `reload` | 开 | `Cmd+Alt+Ctrl+R` 重载配置 |
| `altTab` | 关 | `Alt+Tab` 触发 macOS App Switcher |
| `text` | 关 | Windows 风格文本编辑快捷键 |
| `browser` | 关 | 浏览器标签与刷新快捷键 |
| `system` | 关 | Mission Control、显示桌面、活动监视器等 |
| `screenshot` | 关 | Print Screen / 截图工具兼容 |
| `volume` | 关 | 音量加减与静音 |
| `spaces` | 关 | 虚拟桌面切换、创建、关闭 |
| `apps` | 关 | `Win+1` 到 `Win+9` 应用快速启动 |
| `finderActions` | 关 | Finder 删除、重命名、新建文件夹 |

`windowModifiers` 和 `launcherModifiers` 使用 Hammerspoon 原生修饰键名，不受 `modifierSwap` 影响。默认使用 `Cmd+Alt+Ctrl`，避免覆盖裸 `Cmd+Left`、`Cmd+R`、`Cmd+I` 这类 macOS 常用快捷键。

### 修饰键映射

默认 `modifierSwap = false`：

- `win` 映射到 macOS `cmd`
- `ctrl` 映射到 macOS `ctrl`
- `alt` 映射到 macOS `alt`

如果你想让旧版配置中的交换模式继续生效，可以在 `config.local.lua` 设置：

```lua
return {
	modifierSwap = true,
}
```

为了兼容旧配置，脚本仍会读取 `_G.modifierSwapped` 和 `HAMMERSPOON_MODIFIER_SWAP`，但不再推荐依赖 shell rc 中的环境变量。

## 合盖休眠保护

`power-lid-sleep` 插件只在 MacBook 这类能读取 `AppleClamshellState` 的设备上生效；Mac mini、Mac Studio、iMac 等设备即使误开启配置，也会跳过退出应用和蓝牙动作。

关闭示例：

```lua
return {
	plugins = {
		["power-lid-sleep"] = {
			enabled = false,
			bluetooth = {
				enabled = false,
			},
		},
	},
}
```

默认策略：

- 只在电池供电且合盖时执行。
- RustDesk 正在运行且连续 4 次检查都没有 TCP established 连接时退出 RustDesk。
- 主动睡眠快捷键为 `Cmd+Ctrl+S`；触发后会先清理 `caffeinate`、按配置关闭蓝牙、提示实际执行结果，全部成功后再延迟 2 秒进入睡眠；目标未运行或依赖未检测到会跳过，只有已检测到但处理失败才会取消睡眠。
- 蓝牙保护默认关闭；如需排查蓝牙外设唤醒，可在本机配置里开启 `plugins["power-lid-sleep"].bluetooth.enabled = true`。
- 蓝牙保护依赖 `blueutil`，开启后会在合盖时关闭蓝牙，开盖或唤醒后按进入保护前的状态恢复。
- 缺少 `blueutil` 时只跳过蓝牙保护，RustDesk 空闲退出仍可运行。

安装 `blueutil`：

```zsh
brew install blueutil
```

## 文件结构

```text
hammerspoon/
├── config.lua                  # 仓库默认配置
├── config.local.example.lua    # 本机覆盖示例
├── init/
│   └── init.lua                # Hammerspoon 入口
├── plugins/
│   ├── power-lid-sleep/
│   │   ├── plugin.lua
│   │   ├── app_guard.lua
│   │   ├── bluetooth_guard.lua
│   │   └── lid_state.lua
│   └── win-hotkeys/
│       └── plugin.lua
├── load_scripts.zsh            # 部署脚本
└── README.md
```

部署后的结构：

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

## 排查

- 快捷键不工作：确认 Hammerspoon 已获得辅助功能权限。
- 配置没生效：按 `Cmd+Alt+Ctrl+R` 重载，或查看 Hammerspoon Console。
- 合盖休眠保护不生效：确认运行设备是 MacBook、`plugins["power-lid-sleep"].enabled = true`，且当前是电池供电和合盖状态。
- 蓝牙未关闭：确认已安装 `blueutil`，并在本机配置里开启 `plugins["power-lid-sleep"].bluetooth.enabled = true`。
- 部署脚本找不到 Hammerspoon：确认已安装，或运行 `zsh macos/05deployHammerspoon.sh --install`。
