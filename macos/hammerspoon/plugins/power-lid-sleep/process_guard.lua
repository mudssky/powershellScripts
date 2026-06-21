-- 进程休眠保护模块。
-- 功能：检测并终止合盖休眠场景下的防睡眠命令行进程。
-- 入参：无；模块函数由 power-lid-sleep 插件入口调用。
-- 返回值：模块表。

local M = {}
local logger = nil
local diagnosticLogPath = nil
local activeTasks = {}

-- 追加进程守卫诊断日志到文件。
-- 入参：level 日志级别；message 日志内容。
-- 返回值：无。
local function appendDiagnosticLog(level, message)
	if not diagnosticLogPath then
		return
	end

	local file = io.open(diagnosticLogPath, "a")
	if not file then
		return
	end

	file:write(string.format("%s [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), level, message))
	file:close()
end

-- 记录进程守卫诊断日志。
-- 入参：level 日志级别；message 日志内容。
-- 返回值：无。
local function log(level, message)
	appendDiagnosticLog(level, message)

	if not logger then
		return
	elseif level == "warn" and logger.w then
		logger.w(message)
	elseif logger.i then
		logger.i(message)
	end
end

-- 格式化命令输出，避免日志包含换行。
-- 入参：output 命令输出。
-- 返回值：单行输出文本。
local function compactOutput(output)
	if output == nil then
		return "<nil>"
	end

	local text = tostring(output):gsub("%s+", " ")
	if text == "" then
		return "<empty>"
	end

	return text
end

-- 转义用于单引号 shell 字符串的文本。
-- 入参：value 原始文本。
-- 返回值：可安全放入单引号的文本。
local function shellQuote(value)
	return "'" .. tostring(value):gsub("'", [["'"']]) .. "'"
end

-- 设置日志器。
-- 入参：newLogger Hammerspoon logger 对象；newDiagnosticLogPath 诊断日志文件路径。
-- 返回值：无。
function M.setLogger(newLogger, newDiagnosticLogPath)
	logger = newLogger
	diagnosticLogPath = newDiagnosticLogPath
end

-- 判断防睡眠进程是否正在运行。
-- 入参：processConfig 进程保护配置表。
-- 返回值：布尔值，true 表示存在匹配进程。
function M.isRunning(processConfig)
	local processName = processConfig.name
	if not processName or processName == "" then
		return false
	end

	local command = "pgrep -x " .. shellQuote(processName) .. " >/dev/null 2>&1"
	local _, success = hs.execute(command, true)
	return success == true
end

-- 终止匹配的防睡眠进程。
-- 入参：processConfig 进程保护配置表；showAlert 是否显示提示。
-- 返回值：布尔值，true 表示命令执行成功。
function M.terminate(processConfig, showAlert)
	local processName = processConfig.name
	if not processName or processName == "" then
		return false
	end

	if showAlert ~= false then
		hs.alert.show(string.format("电池合盖，清理 %s 防睡眠进程", processName))
	end

	local signal = processConfig.signal or "TERM"
	local command = string.format(
		"pkill -%s -x %s >/dev/null 2>&1 && sleep 0.5 && ! pgrep -x %s >/dev/null 2>&1",
		signal,
		shellQuote(processName),
		shellQuote(processName)
	)
	local _, success = hs.execute(command, true)
	return success == true
end

-- 移除已结束的后台任务引用。
-- 入参：task 已结束的 hs.task 对象。
-- 返回值：无。
local function removeTask(task)
	for index, activeTask in ipairs(activeTasks) do
		if activeTask == task then
			table.remove(activeTasks, index)
			return
		end
	end
end

-- 后台终止匹配的防睡眠进程。
-- 入参：processConfig 进程保护配置表；callback 完成回调。
-- 返回值：布尔值，true 表示任务已启动。
function M.terminateAsync(processConfig, callback)
	local processName = processConfig.name
	if not processName or processName == "" then
		return false
	end

	local signal = processConfig.signal or "TERM"
	local task
	task = hs.task.new("/usr/bin/pkill", function(exitCode, stdOut, stdErr)
		local succeeded = exitCode == 0 or exitCode == 1
		log(
			succeeded and "info" or "warn",
			string.format(
				"进程后台清理结束: name=%s signal=%s exitCode=%s stdout=%s stderr=%s",
				processName,
				signal,
				tostring(exitCode),
				compactOutput(stdOut),
				compactOutput(stdErr)
			)
		)
		removeTask(task)
		if callback then
			if exitCode == 0 then
				callback(true, "已清理")
			elseif exitCode == 1 then
				callback(true, "未运行")
			else
				callback(false, "清理失败 rc=" .. tostring(exitCode))
			end
		end
	end, nil, { "-" .. signal, "-x", processName })

	if not task then
		log("warn", "进程后台清理任务创建失败: " .. processName)
		return false
	end

	local started = task:start()
	if not started then
		log("warn", "进程后台清理任务启动失败: " .. processName)
		return false
	end

	table.insert(activeTasks, task)
	log("info", "进程后台清理任务已启动: " .. processName)
	return true
end

return M
