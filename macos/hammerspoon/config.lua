-- Hammerspoon 默认配置。
-- 功能：定义仓库默认快捷键组与行为开关。
-- 入参：无。
-- 返回值：配置表，供 init.lua 和 win.lua 读取。

return {
	modifierSwap = false,
	showAlerts = true,
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
