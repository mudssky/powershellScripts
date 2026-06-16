# Hammerspoon 快捷键配置

这个目录维护一套偏精简的 macOS Hammerspoon 配置。默认只启用低冲突快捷键：窗口吸附、锁屏、Finder、Spotlight、系统设置和配置重载；其他 Windows 风格快捷键通过本机配置按需开启。

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

部署脚本会复制 `init.lua`、默认配置和功能脚本到 `~/.hammerspoon/`，保留本机 `config.local.lua`，并启动或重启 Hammerspoon。

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

## 文件结构

```text
hammerspoon/
├── config.lua                  # 仓库默认配置
├── config.local.example.lua    # 本机覆盖示例
├── init/
│   └── init.lua                # Hammerspoon 入口
├── load_scripts.zsh            # 部署脚本
├── win.lua                     # 快捷键功能脚本
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
    └── win.lua
```

## 排查

- 快捷键不工作：确认 Hammerspoon 已获得辅助功能权限。
- 配置没生效：按 `Cmd+Alt+Ctrl+R` 重载，或查看 Hammerspoon Console。
- 部署脚本找不到 Hammerspoon：确认已安装，或运行 `zsh macos/05deployHammerspoon.sh --install`。
