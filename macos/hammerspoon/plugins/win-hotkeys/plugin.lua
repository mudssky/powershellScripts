-- Windows-like shortcuts for macOS using Hammerspoon.
-- 功能：提供低冲突核心快捷键和可选 Windows 风格快捷键组。
-- 入参：无；插件加载器调用 start(context) 传入上下文。
-- 返回值：插件表，供 init.lua 启动。

local plugin = {
	id = "win-hotkeys",
	defaultConfig = {
		enabled = true,
	},
}

local config = {}
local globalConfig = {}
local enabledGroups = {}
local hotkeys = {}
local showAlerts = true

-- 判断功能组是否启用。
-- 入参：groupName 功能组名称。
-- 返回值：布尔值，true 表示该组启用。
local function isGroupEnabled(groupName)
	return enabledGroups[groupName] == true
end

-- 显示可静默关闭的提示。
-- 入参：message 提示文本；duration 展示秒数。
-- 返回值：无。
local function showAlert(message, duration)
	if showAlerts then
		hs.alert.show(message, duration or 1)
	end
end

-- 合并根层兼容配置和插件配置。
-- 入参：fallbackGroups 根层功能组；pluginGroups 插件功能组。
-- 返回值：合并后的功能组配置。
local function mergeEnabledGroups(fallbackGroups, pluginGroups)
	local result = {}

	for key, value in pairs(fallbackGroups or {}) do
		result[key] = value
	end

	for key, value in pairs(pluginGroups or {}) do
		result[key] = value
	end

	return result
end

-- 读取修饰键映射配置。
-- 入参：无。
-- 返回值：包含 winKey、ctrlKey、altKey、cmdKey 的映射表。
local function getModifierKeyMapping()
	local shouldSwap = config.modifierSwap == true
	if config.modifierSwap == nil then
		shouldSwap = globalConfig.modifierSwap == true
	end
	local envSwap = os.getenv("HAMMERSPOON_MODIFIER_SWAP")

	if envSwap ~= nil then
		shouldSwap = envSwap:lower() == "true" or envSwap == "1"
	end

	if _G.modifierSwapped ~= nil then
		shouldSwap = _G.modifierSwapped
	end

	if shouldSwap then
		return {
			winKey = "ctrl",
			ctrlKey = "cmd",
			altKey = "alt",
			cmdKey = "cmd",
		}
	end

	return {
		winKey = "cmd",
		ctrlKey = "ctrl",
		altKey = "alt",
		cmdKey = "cmd",
	}
end

local modKeys = {}

local windowModifiers = { "cmd", "alt", "ctrl" }
local launcherModifiers = { "cmd", "alt", "ctrl" }

-- 获取应用名称映射。
-- 入参：appName 逻辑应用名或旧名称。
-- 返回值：适合 hs.application.launchOrFocus 的应用名称。
local function resolveAppName(appName)
	local appNameMap = {
		["System Preferences"] = "System Settings",
		["系统偏好设置"] = "System Settings",
		["System Settings"] = "System Settings",
		["系统设置"] = "System Settings",
		["Activity Monitor"] = "Activity Monitor",
		["活动监视器"] = "Activity Monitor",
		["System Information"] = "System Information",
		["系统信息"] = "System Information",
	}

	return appNameMap[appName] or appName
end

-- 启动或聚焦应用程序。
-- 入参：appName 应用程序名称。
-- 返回值：布尔值，true 表示启动或聚焦成功。
local function launchOrFocusApp(appName)
	if not appName or appName == "" then
		showAlert("应用程序名称为空", 1)
		return false
	end

	local actualAppName = resolveAppName(appName)
	local success = hs.application.launchOrFocus(actualAppName)
	if not success and actualAppName == "System Settings" then
		success = hs.application.launchOrFocus("System Preferences")
	end

	if not success then
		showAlert(string.format("无法启动应用程序: %s", actualAppName), 2)
	end

	return success
end

-- 创建适配修饰键的快捷键绑定。
-- 入参：modifiers 修饰键列表；key 按键；fn 回调函数；description 描述文本。
-- 返回值：无。
local function bindKey(modifiers, key, fn, description)
	local adaptedModifiers = {}
	for _, mod in ipairs(modifiers) do
		if mod == "win" then
			table.insert(adaptedModifiers, modKeys.winKey)
		elseif mod == "ctrl" then
			table.insert(adaptedModifiers, modKeys.ctrlKey)
		elseif mod == "alt" then
			table.insert(adaptedModifiers, modKeys.altKey)
		elseif mod == "cmd" then
			table.insert(adaptedModifiers, modKeys.cmdKey)
		else
			table.insert(adaptedModifiers, mod)
		end
	end

	local success, err = pcall(function()
		hs.hotkey.bind(adaptedModifiers, key, fn)
	end)

	if not success then
		print(string.format("绑定快捷键失败: %s+%s - %s", table.concat(adaptedModifiers, "+"), key, err))
	elseif description then
		print(string.format("绑定快捷键: %s+%s - %s", table.concat(adaptedModifiers, "+"), key, description))
	end
end

-- 创建不经过 Windows 风格修饰键适配的快捷键绑定。
-- 入参：modifiers macOS 原生修饰键列表；key 按键；fn 回调函数；description 描述文本。
-- 返回值：无。
local function bindRawKey(modifiers, key, fn, description)
	local success, err = pcall(function()
		hs.hotkey.bind(modifiers, key, fn)
	end)

	if not success then
		print(string.format("绑定快捷键失败: %s+%s - %s", table.concat(modifiers, "+"), key, err))
	elseif description then
		print(string.format("绑定快捷键: %s+%s - %s", table.concat(modifiers, "+"), key, description))
	end
end

-- 获取当前窗口和屏幕。
-- 入参：无。
-- 返回值：成功时返回窗口对象和屏幕对象；失败时返回 nil, nil。
local function getWindowAndScreen()
	local win = hs.window.focusedWindow()
	if not win then
		showAlert("没有活动窗口", 1)
		return nil, nil
	end

	local screen = win:screen()
	if not screen then
		showAlert("无法获取屏幕信息", 1)
		return nil, nil
	end

	return win, screen
end

-- 调整系统音量。
-- 入参：delta 音量变化值。
-- 返回值：无。
local function adjustVolume(delta)
	local device = hs.audiodevice.defaultOutputDevice()
	if device then
		local currentVolume = device:volume()
		local newVolume = math.max(0, math.min(100, currentVolume + delta))
		device:setVolume(newVolume)
		showAlert(string.format("音量: %d%%", newVolume), 0.5)
	end
end

-- 切换系统静音状态。
-- 入参：无。
-- 返回值：无。
local function toggleMute()
	local device = hs.audiodevice.defaultOutputDevice()
	if device then
		local isMuted = device:muted()
		device:setMuted(not isMuted)
		showAlert(isMuted and "取消静音" or "静音", 0.5)
	end
end

-- 注册应用切换快捷键。
-- 入参：无。
-- 返回值：无。
local function registerAltTab()
	bindKey({ "alt" }, "tab", function()
		hs.eventtap.keyStroke({ "cmd" }, "tab")
	end, "应用程序切换")
end

-- 注册配置重载快捷键。
-- 入参：无。
-- 返回值：无。
local function registerReload()
	bindRawKey({ "cmd", "alt", "ctrl" }, "r", function()
		hs.reload()
	end, "重载 Hammerspoon 配置")
end

-- 注册窗口吸附快捷键。
-- 入参：无。
-- 返回值：无。
local function registerWindow()
	bindRawKey(windowModifiers, "left", function()
		local win, screen = getWindowAndScreen()
		if win and screen then
			local frame = screen:frame()
			win:setFrame({
				x = frame.x,
				y = frame.y,
				w = frame.w / 2,
				h = frame.h,
			})
		end
	end, "窗口靠左半屏")

	bindRawKey(windowModifiers, "right", function()
		local win, screen = getWindowAndScreen()
		if win and screen then
			local frame = screen:frame()
			win:setFrame({
				x = frame.x + frame.w / 2,
				y = frame.y,
				w = frame.w / 2,
				h = frame.h,
			})
		end
	end, "窗口靠右半屏")

	bindRawKey(windowModifiers, "up", function()
		local win = hs.window.focusedWindow()
		if win then
			if win:isMaximizable() then
				win:maximize()
			else
				showAlert("窗口无法最大化", 1)
			end
		end
	end, "窗口最大化")

	bindRawKey(windowModifiers, "down", function()
		local win = hs.window.focusedWindow()
		if win then
			if win:isMinimizable() then
				win:minimize()
			else
				showAlert("窗口无法最小化", 1)
			end
		end
	end, "窗口最小化")
end

-- 注册核心启动器快捷键。
-- 入参：无。
-- 返回值：无。
local function registerLauncher()
	bindRawKey(launcherModifiers, "l", function()
		hs.caffeinate.lockScreen()
	end, "锁定屏幕")

	bindRawKey(launcherModifiers, "e", function()
		launchOrFocusApp("Finder")
	end, "打开 Finder")

	bindRawKey(launcherModifiers, "space", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey }, "space")
	end, "打开 Spotlight")

	bindRawKey(launcherModifiers, "i", function()
		launchOrFocusApp("System Settings")
	end, "打开系统设置")
end

-- 注册文本编辑快捷键。
-- 入参：无。
-- 返回值：无。
local function registerText()
	local mappings = {
		-- ponytail: 这些全局 Ctrl 文本映射会影响终端 SIGINT/常用控制键，需要时再逐个恢复。
		-- { "a", { modKeys.cmdKey }, "a", "全选" },
		-- { "c", { modKeys.cmdKey }, "c", "复制" },
		-- { "v", { modKeys.cmdKey }, "v", "粘贴" },
		-- { "x", { modKeys.cmdKey }, "x", "剪切" },
		-- { "z", { modKeys.cmdKey }, "z", "撤销" },
		-- { "y", { modKeys.cmdKey, "shift" }, "z", "重做" },
		-- { "s", { modKeys.cmdKey }, "s", "保存" },
		-- { "f", { modKeys.cmdKey }, "f", "查找" },
		-- { "n", { modKeys.cmdKey }, "n", "新建" },
		-- { "o", { modKeys.cmdKey }, "o", "打开" },
		-- { "p", { modKeys.cmdKey }, "p", "打印" },
		-- { "w", { modKeys.cmdKey }, "w", "关闭窗口" },
		-- { "t", { modKeys.cmdKey }, "t", "新建标签页" },
	}

	for _, mapping in ipairs(mappings) do
		local sourceKey = mapping[1]
		local targetModifiers = mapping[2]
		local targetKey = mapping[3]
		local description = mapping[4]
		bindKey({ "ctrl" }, sourceKey, function()
			hs.eventtap.keyStroke(targetModifiers, targetKey)
		end, description)
	end
end

-- 注册浏览器快捷键。
-- 入参：无。
-- 返回值：无。
local function registerBrowser()
	bindKey({ "ctrl" }, "tab", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey, "shift" }, "]")
	end, "下一个标签页")

	bindKey({ "ctrl", "shift" }, "tab", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey, "shift" }, "[")
	end, "上一个标签页")

	bindKey({}, "F5", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey }, "r")
	end, "刷新页面")

	bindKey({ "ctrl" }, "r", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey }, "r")
	end, "刷新页面")

	bindKey({ "ctrl", "shift" }, "t", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey, "shift" }, "t")
	end, "恢复关闭的标签页")
end

-- 注册系统工具快捷键。
-- 入参：无。
-- 返回值：无。
local function registerSystem()
	bindKey({ "win" }, "tab", function()
		hs.spaces.openMissionControl()
	end, "显示所有窗口")

	bindKey({ "win" }, "d", function()
		hs.eventtap.keyStroke({ "fn" }, "F11")
	end, "显示桌面")

	bindKey({ "alt" }, "F4", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey }, "q")
	end, "关闭应用程序")

	bindKey({ "ctrl", "shift" }, "escape", function()
		launchOrFocusApp("Activity Monitor")
	end, "打开活动监视器")

	bindKey({ "win" }, "F12", function()
		launchOrFocusApp("System Information")
	end, "打开关于本机")
end

-- 注册截图快捷键。
-- 入参：无。
-- 返回值：无。
local function registerScreenshot()
	bindKey({}, "F13", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey, "shift" }, "3")
	end, "截取整个屏幕")

	bindKey({ "alt" }, "F13", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey, "shift" }, "4")
		hs.timer.doAfter(0.1, function()
			hs.eventtap.keyStroke({}, "space")
		end)
	end, "截取当前窗口")

	bindKey({ "win", "shift" }, "s", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey, "shift" }, "4")
	end, "截图工具")
end

-- 注册音量快捷键。
-- 入参：无。
-- 返回值：无。
local function registerVolume()
	bindKey({ "ctrl", "alt" }, "up", function()
		adjustVolume(10)
	end, "音量增加")

	bindKey({ "ctrl", "alt" }, "down", function()
		adjustVolume(-10)
	end, "音量减少")

	bindKey({ "ctrl", "alt" }, "m", function()
		toggleMute()
	end, "静音切换")
end

-- 注册虚拟桌面快捷键。
-- 入参：无。
-- 返回值：无。
local function registerSpaces()
	bindKey({ "win", "ctrl" }, "left", function()
		hs.eventtap.keyStroke({ modKeys.ctrlKey }, "left")
	end, "切换到左边的桌面")

	bindKey({ "win", "ctrl" }, "right", function()
		hs.eventtap.keyStroke({ modKeys.ctrlKey }, "right")
	end, "切换到右边的桌面")

	bindKey({ "win", "ctrl" }, "d", function()
		hs.eventtap.keyStroke({ modKeys.ctrlKey }, "up")
		hs.timer.doAfter(0.5, function()
			hs.eventtap.keyStroke({}, "return")
		end)
	end, "创建新的虚拟桌面")

	bindKey({ "win", "ctrl" }, "F4", function()
		hs.eventtap.keyStroke({ modKeys.ctrlKey }, "up")
		hs.timer.doAfter(0.5, function()
			hs.eventtap.keyStroke({}, "delete")
		end)
	end, "关闭当前虚拟桌面")
end

-- 注册应用快速启动快捷键。
-- 入参：无。
-- 返回值：无。
local function registerApps()
	local taskbarApps = config.taskbarApps or globalConfig.taskbarApps or {}

	for i = 1, 9 do
		bindKey({ "win" }, tostring(i), function()
			local app = taskbarApps[i]
			if app then
				launchOrFocusApp(app)
			end
		end, "启动/切换到 " .. (taskbarApps[i] or "应用程序"))
	end
end

-- 注册 Finder 操作快捷键。
-- 入参：无。
-- 返回值：无。
local function registerFinderActions()
	bindKey({}, "F2", function()
		hs.eventtap.keyStroke({}, "return")
	end, "重命名")

	bindKey({}, "delete", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey }, "delete")
	end, "移到废纸篓")

	bindKey({ "shift" }, "delete", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey, "alt" }, "delete")
	end, "永久删除")

	bindKey({ "ctrl", "shift" }, "n", function()
		hs.eventtap.keyStroke({ modKeys.cmdKey, "shift" }, "n")
	end, "新建文件夹")
end

local groupRegistrars = {
	{ "reload", registerReload },
	{ "window", registerWindow },
	{ "launcher", registerLauncher },
	{ "altTab", registerAltTab },
	{ "text", registerText },
	{ "browser", registerBrowser },
	{ "system", registerSystem },
	{ "screenshot", registerScreenshot },
	{ "volume", registerVolume },
	{ "spaces", registerSpaces },
	{ "apps", registerApps },
	{ "finderActions", registerFinderActions },
}

-- 启动快捷键插件。
-- 入参：context 插件上下文，包含 config 与 globalConfig。
-- 返回值：插件运行状态表。
function plugin.start(context)
	globalConfig = context.globalConfig or {}
	config = context.config or {}
	enabledGroups = mergeEnabledGroups(globalConfig.enabledGroups or {}, config.enabledGroups or {})
	hotkeys = config.hotkeys or globalConfig.hotkeys or {}
	showAlerts = config.showAlerts
	if showAlerts == nil then
		showAlerts = globalConfig.showAlerts ~= false
	end

	hs.hotkey.alertDuration = 0
	hs.hints.showTitleThresh = 0

	modKeys = getModifierKeyMapping()
	windowModifiers = hotkeys.windowModifiers or { "cmd", "alt", "ctrl" }
	launcherModifiers = hotkeys.launcherModifiers or { "cmd", "alt", "ctrl" }

	for _, group in ipairs(groupRegistrars) do
		if isGroupEnabled(group[1]) then
			group[2]()
		end
	end

	print("\n=== Hammerspoon 快捷键配置 ===")
	print(string.format("修饰键交换: %s", tostring(modKeys.winKey == "ctrl")))
	print("默认核心组: window, launcher, reload")
	print("可选组: altTab, text, browser, system, screenshot, volume, spaces, apps, finderActions")
	print("================================\n")

	return {
		enabledGroups = enabledGroups,
	}
end

return plugin
