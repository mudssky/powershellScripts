-- 进程休眠保护模块。
-- 功能：检测并终止合盖休眠场景下的防睡眠命令行进程。
-- 入参：无；模块函数由 power-lid-sleep 插件入口调用。
-- 返回值：模块表。

local M = {}

-- 转义用于单引号 shell 字符串的文本。
-- 入参：value 原始文本。
-- 返回值：可安全放入单引号的文本。
local function shellQuote(value)
	return "'" .. tostring(value):gsub("'", [["'"']]) .. "'"
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

return M
