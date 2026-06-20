-- Hammerspoon 默认配置。
-- 功能：定义仓库默认快捷键组与行为开关。
-- 入参：无。
-- 返回值：配置表，供 init.lua 和插件读取。

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
	plugins = {
		["win-hotkeys"] = {
			enabled = true,
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
			processes = {
				{
					name = "caffeinate",
					terminateWhenLidClosed = true,
					requiredIdleChecks = 1,
					signal = "TERM",
				},
			},
			bluetooth = {
				enabled = true,
				mode = "powerOff",
				restoreOnWake = true,
				enforceWhileLidClosed = true,
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
