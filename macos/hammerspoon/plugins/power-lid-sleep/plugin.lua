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
	local requiredIdleChecks = numberOrDefault(config.requiredIdleChecks, 4, 1)
	local checkIntervalSeconds = numberOrDefault(config.checkIntervalSeconds, 15, 5)
	local state = {
		appIdleChecks = {},
		processIdleChecks = {},
		bluetoothOriginalPower = nil,
		bluetoothWasChanged = false,
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

	-- 按配置关闭蓝牙。
	-- 入参：无。
	-- 返回值：无。
	local function guardBluetooth()
		local bluetoothConfig = config.bluetooth or {}
		if bluetoothConfig.enabled ~= true or bluetoothConfig.mode ~= "powerOff" then
			return
		end

		local currentPower = bluetoothGuard.powerState()
		if currentPower == nil then
			log.w("跳过蓝牙休眠保护：未找到 blueutil 或无法读取蓝牙状态")
			return
		end

		if state.bluetoothOriginalPower == nil then
			state.bluetoothOriginalPower = currentPower
		end

		if currentPower == 1 then
			if bluetoothGuard.powerOff() then
				state.bluetoothWasChanged = true
				log.i("电池合盖，已关闭蓝牙")
			else
				log.w("蓝牙关闭失败，请确认 blueutil 可用")
			end
		end
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
				if idleChecks >= requiredIdleChecks then
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

	check()
	return state
end

return plugin
