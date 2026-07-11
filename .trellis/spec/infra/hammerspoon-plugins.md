# Hammerspoon Plugin Contract

## Scenario: macOS Hammerspoon 插件目录

### 1. Scope / Trigger

- Trigger: 修改 `macos/hammerspoon/` 下的 Hammerspoon 功能、部署脚本、插件目录或验证契约时使用。
- Scope: `macos/hammerspoon/init/init.lua`、`macos/hammerspoon/plugins/**`、`macos/hammerspoon/load_scripts.zsh`、`macos/09deployHammerspoon.zsh`、`macos/99verifyInstall.zsh` 和 `profile/installer/apps-config.json` 中 Hammerspoon 相关依赖。

### 2. Signatures

- 插件目录：`macos/hammerspoon/plugins/<plugin-id>/plugin.lua`
- 插件入口返回表：

```lua
return {
	id = "<plugin-id>",
	defaultConfig = {},
	start = function(context)
		return {}
	end,
}
```

- 插件上下文：

```lua
{
	id = "<plugin-id>",
	config = {},
	globalConfig = {},
	configDir = hs.configdir,
	scriptsDir = hs.configdir .. "/scripts",
	pluginsDir = hs.configdir .. "/scripts/plugins",
	log = hs.logger.new("<plugin-id>", "info"),
}
```

### 3. Contracts

- `plugin.id` 必须和目录名一致；不一致时 `init.lua` 记录错误并不启动该插件。
- `defaultConfig.enabled = false` 表示插件默认关闭；高影响插件必须默认关闭。
- `start(context)` 只在合并后的 `config.enabled ~= false` 时调用。
- `start(context)` 返回的 watcher、timer 或状态表必须由 `init.lua` 存入 `_G.HammerspoonPluginState[pluginId]`，避免被 Lua 垃圾回收。
- 插件私有模块应放在同一插件目录下，用 `context.pluginsDir .. "/" .. plugin.id .. "/<module>.lua"` 加载。
- `load_scripts.zsh` 只部署 `plugins/**/*.lua`、`init.lua`、`config.lua` 和首次生成的 `config.local.lua`；新增插件文件必须进入 manifest。
- 删除或迁移托管文件时，依赖 manifest 清理旧路径，例如从 `scripts/win.lua` 迁移到 `scripts/plugins/win-hotkeys/plugin.lua`。
- 源文件与目标内容相同时不得备份或复制；manifest 内容相同时不得重写。
- `09deployHammerspoon.zsh` 只包装 loader，不修改仓库脚本执行权限；dry-run 不探测或启动 GUI 应用。

### 4. Validation & Error Matrix

| Condition | Behavior |
|-----------|----------|
| 插件入口文件不存在 | `init.lua` 记录 `缺少插件文件`，插件计为失败 |
| 插件没有返回 table | `init.lua` 记录 `插件必须返回 table`，插件计为失败 |
| `plugin.id` 与目录名不一致 | `init.lua` 记录 id 不匹配，插件计为失败 |
| 插件缺少 `start` 函数 | `init.lua` 记录 `插件缺少 start 函数`，插件计为失败 |
| 插件 `start` 抛错 | `pcall` 捕获并记录 `插件启动失败`，其余插件继续启动 |
| 高影响插件在不支持设备上运行 | 插件应记录跳过原因，不执行高影响动作 |
| 外部 CLI 缺失 | 相关功能降级跳过，不影响同插件内其他保护逻辑 |

### 5. Good/Base/Bad Cases

- Good: `plugins/power-lid-sleep/plugin.lua` 默认关闭，启动时先检查 `AppleClamshellState`，Mac mini 上不退出应用、不关闭蓝牙。
- Base: `plugins/win-hotkeys/plugin.lua` 默认开启，并兼容根层 `enabledGroups`、`modifierSwap`、`hotkeys` 和 `taskbarApps`。
- Bad: 在 `init.lua` 里直接 `dofile("scripts/foo.lua")`，绕过插件清单、配置合并和状态保存。
- Bad: 插件启动 watcher 后不返回状态表，导致 watcher 可能被回收。

### 6. Tests Required

- 运行 `zsh -n macos/hammerspoon/load_scripts.zsh`、`zsh -n macos/09deployHammerspoon.zsh`、`zsh -n macos/99verifyInstall.zsh`。
- 运行 `zsh macos/hammerspoon/load_scripts.zsh --dry-run --no-launch --install`，确认输出包含所有插件文件和 manifest 条目，并清理被移除的托管旧路径。
- 使用 Lua parser 或 Hammerspoon 控制台验证所有 `plugins/**/*.lua` 和 `init/init.lua` 语法。
- 修改 `macos/99verifyInstall.zsh` 时运行根目录 QA；若涉及 pwsh 相关验证契约，执行 `pnpm test:pwsh:all` 或记录 Linux Docker 分支不可用原因。

### 7. Wrong vs Correct

#### Wrong

```lua
-- init.lua 中直接加载功能脚本，功能配置散在根层。
dofile(hs.configdir .. "/scripts/win.lua")
```

#### Correct

```lua
-- init.lua 只加载显式插件清单，插件自己拥有默认配置和启动入口。
local plugin = dofile(hs.configdir .. "/scripts/plugins/win-hotkeys/plugin.lua")
local config = mergeConfig(plugin.defaultConfig, HammerspoonConfig.plugins[plugin.id] or {})
_G.HammerspoonPluginState[plugin.id] = plugin.start({ config = config })
```
