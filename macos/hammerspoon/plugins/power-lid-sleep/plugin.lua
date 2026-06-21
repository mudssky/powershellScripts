-- 合盖休眠保护插件。
-- 功能：在 MacBook 电池合盖时退出空闲应用并关闭蓝牙，降低异常唤醒和耗电。
-- 入参：无；插件加载器调用 start(context) 传入上下文。
-- 返回值：插件表，供 init.lua 启动。

local plugin = {
	id = "power-lid-sleep",
	defaultConfig = {
		enabled = false,
		requireClamshell = true,
		unsupportedDevicePolicy = "skip",
		checkIntervalSeconds = 15,
		requiredIdleChecks = 4,
		onlyOnBattery = true,
		apps = {},
		processes = {},
		bluetooth = {
			enabled = false,
			mode = "powerOff",
			restoreOnWake = true,
			enforceWhileLidClosed = true,
		},
		activeSleepHotkey = {
			enabled = true,
			modifiers = { "cmd", "ctrl" },
			key = "s",
			delaySeconds = 2,
		},
	},
}

-- 加载插件私有模块。
-- 入参：context 插件上下文；moduleName 模块文件名，不含 .lua。
-- 返回值：模块表。
local function loadModule(context, moduleName)
	local path = context.pluginsDir .. "/" .. plugin.id .. "/" .. moduleName .. ".lua"
	return dofile(path)
end

-- 判断当前是否电池供电。
-- 入参：无。
-- 返回值：布尔值，true 表示正在使用电池。
local function onBattery()
	return hs.battery.powerSource() == "Battery Power"
end

-- 读取数字配置并限制下限。
-- 入参：value 配置值；fallback 默认值；minimum 最小值。
-- 返回值：有效数字。
local function numberOrDefault(value, fallback, minimum)
	local number = tonumber(value) or fallback
	if number < minimum then
		return minimum
	end
	return number
end

-- 读取进程清理所需的连续检查次数。
-- 入参：processConfig 进程保护配置。
-- 返回值：有效检查次数；默认 1 次以便合盖后尽快清理防睡眠进程。
local function processRequiredIdleChecks(processConfig)
	return numberOrDefault(processConfig.requiredIdleChecks, 1, 1)
end

-- 启动合盖休眠保护插件。
-- 入参：context 插件上下文，包含 config、pluginsDir 和 log。
-- 返回值：插件运行状态表，保存 watcher 和计数状态。
function plugin.start(context)
	local config = context.config or {}
	local globalConfig = context.globalConfig or {}
	local log = context.log
	local lidState = loadModule(context, "lid_state")
	local appGuard = loadModule(context, "app_guard")
	local bluetoothGuard = loadModule(context, "bluetooth_guard")
	local processGuard = loadModule(context, "process_guard")
	if type(bluetoothGuard.setLogger) == "function" then
		local logDir = context.configDir .. "/logs"
		if not hs.fs.pathToAbsolute(logDir) then
			hs.fs.mkdir(logDir)
		end
		bluetoothGuard.setLogger(log, logDir .. "/power-lid-sleep.log")
	end
	local requiredIdleChecks = numberOrDefault(config.requiredIdleChecks, 4, 1)
	local checkIntervalSeconds = numberOrDefault(config.checkIntervalSeconds, 15, 5)
	local state = {
		appIdleChecks = {},
		processIdleChecks = {},
		bluetoothOriginalPower = nil,
		bluetoothWasChanged = false,
		activeSleepHotkey = nil,
	}
	local showAlerts = config.showAlerts
	if showAlerts == nil then
		showAlerts = globalConfig.showAlerts ~= false
	end

	if config.requireClamshell ~= false and not lidState.supportsClamshell() then
		log.i("当前设备不支持 AppleClamshellState，跳过合盖休眠保护: " .. lidState.hardwareModel())
		return state
	end

	-- 重置所有应用空闲计数。
	-- 入参：无。
	-- 返回值：无。
	local function resetAppIdleChecks()
		state.appIdleChecks = {}
	end

	-- 重置所有进程空闲计数。
	-- 入参：无。
	-- 返回值：无。
	local function resetProcessIdleChecks()
		state.processIdleChecks = {}
	end

	-- 判断是否满足执行休眠保护动作的基础条件。
	-- 入参：无。
	-- 返回值：布尔值，true 表示满足条件。
	local function shouldGuardSleep()
		if config.onlyOnBattery ~= false and not onBattery() then
			return false
		end

		return lidState.isClosed()
	end

	-- 恢复蓝牙到进入保护前的状态。
	-- 入参：无。
	-- 返回值：无。
	local function restoreBluetooth()
		local bluetoothConfig = config.bluetooth or {}
		if bluetoothConfig.enabled ~= true or bluetoothConfig.restoreOnWake == false then
			return
		end

		if state.bluetoothWasChanged and state.bluetoothOriginalPower == 1 then
			if bluetoothGuard.powerOn() then
				log.i("已恢复蓝牙电源")
			else
				log.w("蓝牙恢复失败，请确认 blueutil 可用")
			end
		end

		state.bluetoothWasChanged = false
		state.bluetoothOriginalPower = nil
	end

	-- 按配置关闭蓝牙，并返回处理结果。
	-- 入参：无。
	-- 返回值：结果文本和布尔值；布尔值为 false 时主动睡眠应取消。
	local function guardBluetooth()
		local bluetoothConfig = config.bluetooth or {}
		if bluetoothConfig.enabled ~= true or bluetoothConfig.mode ~= "powerOff" then
			return "蓝牙：未启用关闭", true
		end

		if not bluetoothGuard.available() then
			return "蓝牙：未检测到 blueutil，跳过", true
		end

		local currentPower = bluetoothGuard.powerState()
		if currentPower == nil then
			log.w("蓝牙状态读取失败，尝试直接关闭蓝牙")
			if bluetoothGuard.powerOff() then
				state.bluetoothWasChanged = true
				state.bluetoothOriginalPower = nil
				log.i("蓝牙状态读取失败，但已直接关闭蓝牙")
				return "蓝牙：读取失败，已关闭", true
			end
			log.w("蓝牙状态读取失败，直接关闭蓝牙也失败")
			return "蓝牙：读取和关闭失败", false
		end

		if state.bluetoothOriginalPower == nil then
			state.bluetoothOriginalPower = currentPower
		end

		if currentPower == 1 then
			if bluetoothGuard.powerOff() then
				state.bluetoothWasChanged = true
				log.i("电池合盖，已关闭蓝牙")
				return "蓝牙：已关闭", true
			else
				log.w("蓝牙关闭失败，请确认 blueutil 可用")
				return "蓝牙：关闭失败", false
			end
		end

		return "蓝牙：已是关闭", true
	end

	-- 检查并退出空闲应用。
	-- 入参：无。
	-- 返回值：无。
	local function guardApps()
		for _, appConfig in ipairs(config.apps or {}) do
			if appConfig.quitWhenIdle ~= false and appGuard.isRunning(appConfig) then
				if appGuard.activeConnections(appConfig) > 0 then
					state.appIdleChecks[appConfig.name] = 0
				else
					local idleChecks = (state.appIdleChecks[appConfig.name] or 0) + 1
					state.appIdleChecks[appConfig.name] = idleChecks
					if idleChecks >= requiredIdleChecks then
						appGuard.quit(appConfig, showAlerts)
						state.appIdleChecks[appConfig.name] = 0
					end
				end
			else
				state.appIdleChecks[appConfig.name] = 0
			end
		end
	end

	-- 检查并终止防睡眠进程。
	-- 入参：无。
	-- 返回值：无。
	local function guardProcesses()
		for _, processConfig in ipairs(config.processes or {}) do
			local processName = processConfig.name
			if processName and processName ~= "" and processConfig.terminateWhenLidClosed ~= false and processGuard.isRunning(processConfig) then
				local idleChecks = (state.processIdleChecks[processName] or 0) + 1
				state.processIdleChecks[processName] = idleChecks
				if idleChecks >= processRequiredIdleChecks(processConfig) then
					if processGuard.terminate(processConfig, showAlerts) then
						log.i("电池合盖，已清理防睡眠进程: " .. processName)
					else
						log.w("防睡眠进程清理失败: " .. processName)
					end
					state.processIdleChecks[processName] = 0
				end
			elseif processName and processName ~= "" then
				state.processIdleChecks[processConfig.name] = 0
			end
		end
	end

	-- 不依赖合盖状态，直接清理已配置的防睡眠进程。
	-- 入参：showProcessAlerts 是否显示每个进程的独立提示。
	-- 返回值：结果列表和布尔值；布尔值为 false 时主动睡眠应取消。
	local function terminateSleepPreventingProcesses(showProcessAlerts)
		local results = {}
		local allSucceeded = true
		for _, processConfig in ipairs(config.processes or {}) do
			local processName = processConfig.name
			if processName and processName ~= "" and processConfig.terminateWhenLidClosed ~= false and processGuard.isRunning(processConfig) then
				if processGuard.terminate(processConfig, showProcessAlerts == true and showAlerts ~= false) then
					log.i("睡眠事件触发，已清理防睡眠进程: " .. processName)
					table.insert(results, processName .. "：已清理")
				else
					log.w("睡眠事件触发，防睡眠进程清理失败: " .. processName)
					table.insert(results, processName .. "：清理失败")
					allSucceeded = false
				end
				state.processIdleChecks[processName] = 0
			elseif processName and processName ~= "" then
				table.insert(results, processName .. "：未运行")
			end
		end

		if #results == 0 then
			table.insert(results, "防睡眠进程：未配置")
		end

		return results, allSucceeded
	end

	-- 执行主动睡眠动作。
	-- 入参：无。
	-- 返回值：无。
	local function activeSleep()
		local activeSleepConfig = config.activeSleepHotkey or {}
		local delaySeconds = numberOrDefault(activeSleepConfig.delaySeconds, 2, 0)
		local actionResults, processesSucceeded = terminateSleepPreventingProcesses(false)
		local bluetoothResult, bluetoothSucceeded = guardBluetooth()
		table.insert(actionResults, bluetoothResult)

		local shouldSleep = processesSucceeded and bluetoothSucceeded
		if shouldSleep then
			table.insert(actionResults, string.format("%.0f 秒后进入睡眠", delaySeconds))
		else
			table.insert(actionResults, "已取消睡眠")
		end

		if showAlerts ~= false then
			hs.alert.show(table.concat(actionResults, "\n"), math.max(1.5, delaySeconds))
		end

		if not shouldSleep then
			return
		end

		hs.timer.doAfter(delaySeconds, function()
			hs.execute("/usr/bin/pmset sleepnow >/dev/null 2>&1", true)
		end)
	end

	-- 注册主动睡眠快捷键。
	-- 入参：无。
	-- 返回值：无。
	local function registerActiveSleepHotkey()
		local activeSleepConfig = config.activeSleepHotkey or {}
		if activeSleepConfig.enabled == false then
			return
		end

		local modifiers = activeSleepConfig.modifiers or { "cmd", "ctrl" }
		local key = activeSleepConfig.key or "s"
		state.activeSleepHotkey = hs.hotkey.bind(modifiers, key, activeSleep)
		log.i("已绑定主动睡眠快捷键: " .. table.concat(modifiers, "+") .. "+" .. key)
	end

	-- 执行一次休眠保护检查。
	-- 入参：无。
	-- 返回值：无。
	local function check()
		if not shouldGuardSleep() then
			resetAppIdleChecks()
			resetProcessIdleChecks()
			restoreBluetooth()
			return
		end

		guardApps()
		guardProcesses()
		guardBluetooth()
	end

	state.timer = hs.timer.doEvery(checkIntervalSeconds, check)
	state.caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
		if event == hs.caffeinate.watcher.screensDidSleep
			or event == hs.caffeinate.watcher.systemWillSleep
			or event == hs.caffeinate.watcher.systemDidWake
			or event == hs.caffeinate.watcher.screensDidWake
			or event == hs.caffeinate.watcher.screensDidUnlock then
			check()
		end
	end)
	state.caffeinateWatcher:start()
	state.batteryWatcher = hs.battery.watcher.new(check)
	state.batteryWatcher:start()

	registerActiveSleepHotkey()
	check()
	return state
end

return plugin
