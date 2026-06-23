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
			alternate = {
				enabled = true,
				modifiers = { "cmd", "alt", "ctrl" },
				key = "s",
			},
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

-- 转义用于单引号 shell 字符串的文本。
-- 入参：value 原始文本。
-- 返回值：可安全放入单引号的文本。
local function shellQuote(value)
	return "'" .. tostring(value):gsub("'", [["'"']]) .. "'"
end

-- 删除文件。
-- 入参：path 文件路径。
-- 返回值：无。
local function removeFile(path)
	if path then
		os.remove(path)
	end
end

-- 读取完整文本文件。
-- 入参：path 文件路径。
-- 返回值：读取成功时返回文本，失败时返回 nil。
local function readTextFile(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()
	return content
end

-- 打开 macOS 蓝牙隐私授权页面。
-- 入参：无。
-- 返回值：无。
local function openBluetoothPrivacySettings()
	local url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
	hs.execute("/usr/bin/open " .. shellQuote(url) .. " >/dev/null 2>&1", false)
	hs.timer.doAfter(0.5, function()
		hs.urlevent.openURL(url)
	end)
end

-- 追加主动睡眠诊断日志到文件。
-- 入参：diagnosticLogPath 诊断日志路径；message 日志内容。
-- 返回值：无。
local function appendDiagnosticLog(diagnosticLogPath, message)
	if not diagnosticLogPath then
		return
	end

	local file = io.open(diagnosticLogPath, "a")
	if not file then
		return
	end

	file:write(string.format("%s [info] %s\n", os.date("%Y-%m-%d %H:%M:%S"), message))
	file:close()
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
	local logDir = context.configDir .. "/logs"
	if not hs.fs.pathToAbsolute(logDir) then
		hs.fs.mkdir(logDir)
	end
	local diagnosticLogPath = logDir .. "/power-lid-sleep.log"
	local bluetoothRestoreMarkerPath = logDir .. "/power-lid-sleep.restore-bluetooth"
	if type(bluetoothGuard.setLogger) == "function" then
		bluetoothGuard.setLogger(log, diagnosticLogPath)
	end
	if type(processGuard.setLogger) == "function" then
		processGuard.setLogger(log, diagnosticLogPath)
	end
	local requiredIdleChecks = numberOrDefault(config.requiredIdleChecks, 4, 1)
	local checkIntervalSeconds = numberOrDefault(config.checkIntervalSeconds, 15, 5)
	local state = {
		appIdleChecks = {},
		processIdleChecks = {},
		bluetoothOriginalPower = nil,
		bluetoothWasChanged = false,
		activeSleepHotkeys = {},
		activeSleepResultTimer = nil,
		bluetoothPermissionTimer = nil,
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

		local restoreMarked = hs.fs.pathToAbsolute(bluetoothRestoreMarkerPath) ~= nil
		if restoreMarked then
			appendDiagnosticLog(diagnosticLogPath, "检测到主动睡眠蓝牙恢复标记")
		end

		if restoreMarked or (state.bluetoothWasChanged and state.bluetoothOriginalPower ~= 0) then
			local helperPath = context.pluginsDir .. "/" .. plugin.id .. "/active_sleep.zsh"
			local command = string.format(
				"/bin/zsh %s --restore-bluetooth %s >/dev/null 2>&1 &",
				shellQuote(helperPath),
				shellQuote(bluetoothRestoreMarkerPath)
			)
			hs.execute(command, false)
			log.i("已安排独立执行器恢复蓝牙电源")
			appendDiagnosticLog(diagnosticLogPath, "已安排独立执行器恢复蓝牙电源")
			state.bluetoothWasChanged = false
			state.bluetoothOriginalPower = nil
			return
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

		if type(bluetoothGuard.powerOffAsync) == "function" then
			if bluetoothGuard.powerOffAsync() then
				state.bluetoothWasChanged = true
				state.bluetoothOriginalPower = nil
				log.i("已安排后台关闭蓝牙")
				return "蓝牙：后台关闭中", true
			end

			log.w("蓝牙后台关闭任务启动失败")
			return "蓝牙：关闭任务启动失败", false
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

	-- 后台关闭蓝牙，并通过回调返回处理结果。
	-- 入参：callback 完成回调，接收结果文本和成功状态。
	-- 返回值：布尔值，true 表示已异步处理。
	local function guardBluetoothAsync(callback)
		local bluetoothConfig = config.bluetooth or {}
		if bluetoothConfig.enabled ~= true or bluetoothConfig.mode ~= "powerOff" then
			callback("蓝牙：未启用关闭", true)
			return true
		end

		if not bluetoothGuard.available() then
			callback("蓝牙：未检测到 blueutil，跳过", true)
			return true
		end

		if type(bluetoothGuard.powerOffAsync) ~= "function" then
			return false
		end

		local started = bluetoothGuard.powerOffAsync(function(succeeded, detail)
			if succeeded then
				state.bluetoothWasChanged = true
				state.bluetoothOriginalPower = nil
				log.i("蓝牙后台关闭完成")
				callback("蓝牙：" .. detail, true)
			else
				log.w("蓝牙后台关闭失败: " .. tostring(detail))
				callback("蓝牙：" .. detail, false)
			end
		end)

		if not started then
			callback("蓝牙：关闭任务启动失败", false)
		end

		return true
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
			if processName and processName ~= "" and processConfig.terminateWhenLidClosed ~= false and showProcessAlerts ~= true and type(processGuard.terminateAsync) == "function" then
				if processGuard.terminateAsync(processConfig) then
					log.i("睡眠事件触发，已安排后台清理防睡眠进程: " .. processName)
					table.insert(results, processName .. "：后台清理中")
				else
					log.w("睡眠事件触发，防睡眠进程后台清理任务启动失败: " .. processName)
					table.insert(results, processName .. "：清理任务启动失败")
					allSucceeded = false
				end
				state.processIdleChecks[processName] = 0
			elseif processName and processName ~= "" and processConfig.terminateWhenLidClosed ~= false and processGuard.isRunning(processConfig) then
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

	-- 后台清理防睡眠进程，并在全部结束后返回汇总结果。
	-- 入参：callback 完成回调，接收结果列表和成功状态。
	-- 返回值：无。
	local function terminateSleepPreventingProcessesAsync(callback)
		local processConfigs = {}
		for _, processConfig in ipairs(config.processes or {}) do
			local processName = processConfig.name
			if processName and processName ~= "" and processConfig.terminateWhenLidClosed ~= false then
				table.insert(processConfigs, processConfig)
			end
		end

		if #processConfigs == 0 then
			callback({ "防睡眠进程：未配置" }, true)
			return
		end

		local results = {}
		local remaining = #processConfigs
		local allSucceeded = true

		local function finishOne()
			remaining = remaining - 1
			if remaining == 0 then
				callback(results, allSucceeded)
			end
		end

		for _, processConfig in ipairs(processConfigs) do
			local processName = processConfig.name
			local started = type(processGuard.terminateAsync) == "function"
				and processGuard.terminateAsync(processConfig, function(succeeded, detail)
					table.insert(results, processName .. "：" .. detail)
					if not succeeded then
						allSucceeded = false
					end
					state.processIdleChecks[processName] = 0
					finishOne()
				end)

			if not started then
				table.insert(results, processName .. "：清理任务启动失败")
				allSucceeded = false
				state.processIdleChecks[processName] = 0
				finishOne()
			end
		end
	end

	-- 完成主动睡眠前置动作并按结果提示。
	-- 入参：actionResults 结果列表；shouldSleep 是否继续睡眠；delaySeconds 延迟秒数。
	-- 返回值：无。
	local function finishActiveSleep(actionResults, shouldSleep, delaySeconds)
		if shouldSleep then
			table.insert(actionResults, string.format("%.0f 秒后进入睡眠", delaySeconds))
			appendDiagnosticLog(diagnosticLogPath, "主动睡眠前置动作成功，准备进入睡眠")
		else
			table.insert(actionResults, "已取消睡眠")
			appendDiagnosticLog(diagnosticLogPath, "主动睡眠前置动作失败，已取消睡眠")
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

	-- 执行主动睡眠动作。
	-- 入参：无。
	-- 返回值：无。
	local function activeSleep()
		appendDiagnosticLog(diagnosticLogPath, "主动睡眠快捷键已触发")
		local helperPath = context.pluginsDir .. "/" .. plugin.id .. "/active_sleep.zsh"
		local resultPath = context.configDir .. "/logs/power-lid-sleep.result"
		removeFile(resultPath)
		if showAlerts ~= false then
			hs.alert.show("主动睡眠已触发，正在执行前置动作", 1.2)
		end

		local command = string.format("/bin/zsh %s %s >/dev/null 2>&1 &", shellQuote(helperPath), shellQuote(resultPath))
		hs.execute(command, false)

		local attempts = 0
		if state.activeSleepResultTimer then
			state.activeSleepResultTimer:stop()
			state.activeSleepResultTimer = nil
		end
		state.activeSleepResultTimer = hs.timer.doEvery(0.25, function()
			attempts = attempts + 1
			local result = readTextFile(resultPath)
			if result then
				state.activeSleepResultTimer:stop()
				state.activeSleepResultTimer = nil
				removeFile(resultPath)
				local status = result:match("^status=([^\n]*)") or "unknown"
				local message = result:gsub("^status=[^\n]*\n", "")
				message = message:gsub("%s+$", "")
				if showAlerts ~= false then
					hs.alert.show(message, 4)
				end
				if status ~= "ok" and message:find("蓝牙", 1, true) then
					openBluetoothPrivacySettings()
				end
				return
			end

			if attempts >= 24 then
				state.activeSleepResultTimer:stop()
				state.activeSleepResultTimer = nil
				appendDiagnosticLog(diagnosticLogPath, "主动睡眠执行器结果读取超时")
				if showAlerts ~= false then
					hs.alert.show("主动睡眠执行器无结果，请查看日志", 3)
				end
			end
		end)
	end

	-- 启动时预检蓝牙权限，提前触发 macOS 授权流程。
	-- 入参：无。
	-- 返回值：无。
	local function checkBluetoothPermission()
		local bluetoothConfig = config.bluetooth or {}
		if bluetoothConfig.enabled ~= true or bluetoothConfig.mode ~= "powerOff" then
			return
		end

		local helperPath = context.pluginsDir .. "/" .. plugin.id .. "/active_sleep.zsh"
		local resultPath = context.configDir .. "/logs/power-lid-sleep.bluetooth-permission.result"
		removeFile(resultPath)
		appendDiagnosticLog(diagnosticLogPath, "蓝牙权限预检已触发")
		local command = string.format(
			"/bin/zsh %s --check-bluetooth-permission %s >/dev/null 2>&1 &",
			shellQuote(helperPath),
			shellQuote(resultPath)
		)
		hs.execute(command, false)

		local attempts = 0
		if state.bluetoothPermissionTimer then
			state.bluetoothPermissionTimer:stop()
			state.bluetoothPermissionTimer = nil
		end
		state.bluetoothPermissionTimer = hs.timer.doEvery(0.5, function()
			attempts = attempts + 1
			local result = readTextFile(resultPath)
			if result then
				state.bluetoothPermissionTimer:stop()
				state.bluetoothPermissionTimer = nil
				removeFile(resultPath)
				local status = result:match("^status=([^\n]*)") or "unknown"
				local message = result:gsub("^status=[^\n]*\n", "")
				message = message:gsub("%s+$", "")
				appendDiagnosticLog(diagnosticLogPath, "蓝牙权限预检结果: " .. message)
				if status ~= "ok" and showAlerts ~= false then
					hs.alert.show(message, 5)
				end
				if status ~= "ok" then
					openBluetoothPrivacySettings()
				end
				return
			end

			if attempts >= 20 then
				state.bluetoothPermissionTimer:stop()
				state.bluetoothPermissionTimer = nil
				appendDiagnosticLog(diagnosticLogPath, "蓝牙权限预检结果读取超时")
				if showAlerts ~= false then
					hs.alert.show("蓝牙权限预检无结果，请查看日志", 3)
				end
			end
		end)
	end

	-- 绑定单个主动睡眠快捷键。
	-- 入参：hotkeyConfig 快捷键配置；label 快捷键标签。
	-- 返回值：无。
	local function bindActiveSleepHotkey(hotkeyConfig, label)
		if hotkeyConfig.enabled == false then
			return
		end

		local modifiers = hotkeyConfig.modifiers or { "cmd", "ctrl" }
		local key = hotkeyConfig.key or "s"
		local hotkey = hs.hotkey.bind(modifiers, key, activeSleep)
		table.insert(state.activeSleepHotkeys, hotkey)
		local hotkeyText = table.concat(modifiers, "+") .. "+" .. key
		log.i("已绑定主动睡眠快捷键(" .. label .. "): " .. hotkeyText)
		appendDiagnosticLog(diagnosticLogPath, "已绑定主动睡眠快捷键(" .. label .. "): " .. hotkeyText)
	end

	-- 注册主动睡眠快捷键。
	-- 入参：无。
	-- 返回值：无。
	local function registerActiveSleepHotkey()
		local activeSleepConfig = config.activeSleepHotkey or {}
		if activeSleepConfig.enabled == false then
			appendDiagnosticLog(diagnosticLogPath, "主动睡眠快捷键配置已关闭")
			return
		end

		bindActiveSleepHotkey(activeSleepConfig, "主")
		if type(activeSleepConfig.alternate) == "table" then
			bindActiveSleepHotkey(activeSleepConfig.alternate, "备用")
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
	hs.timer.doAfter(1, checkBluetoothPermission)
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
