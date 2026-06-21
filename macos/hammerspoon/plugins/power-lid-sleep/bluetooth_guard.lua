-- 蓝牙休眠保护模块。
-- 功能：在合盖电池场景关闭蓝牙，并按需恢复原状态。
-- 入参：无；模块函数由 power-lid-sleep 插件入口调用。
-- 返回值：模块表。

local M = {}
local cachedBlueutilPath = nil
local shellPath = [[PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]]
local logger = nil
local diagnosticLogPath = nil

-- 追加蓝牙守卫诊断日志到文件。
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

-- 记录蓝牙守卫诊断日志。
-- 入参：level 日志级别；message 日志内容。
-- 返回值：无。
local function log(level, message)
	appendDiagnosticLog(level, message)

	if not logger then
		return
	elseif level == "warn" and logger.w then
		logger.w(message)
	elseif level == "error" and logger.e then
		logger.e(message)
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

-- 查找 blueutil 可执行文件。
-- 入参：无。
-- 返回值：成功时返回可执行文件路径；失败时返回 nil。
local function blueutilPath()
	if cachedBlueutilPath ~= nil then
		return cachedBlueutilPath
	end

	local output, success = hs.execute(shellPath .. " command -v blueutil 2>/dev/null", true)
	if success ~= true or not output or output == "" then
		log("warn", string.format("blueutil 路径检测失败: success=%s output=%s", tostring(success), compactOutput(output)))
		return nil
	end

	cachedBlueutilPath = output:gsub("%s+", "")
	log("info", "blueutil 路径: " .. cachedBlueutilPath)
	return cachedBlueutilPath
end

-- 判断 blueutil 是否可用。
-- 入参：无。
-- 返回值：布尔值，true 表示可执行 blueutil。
function M.available()
	return blueutilPath() ~= nil
end

-- 读取蓝牙电源状态。
-- 入参：无。
-- 返回值：成功时返回数字 0 或 1；失败时返回 nil。
function M.powerState()
	if not M.available() then
		return nil
	end

	local command = string.format("%s %s --power 2>/dev/null", shellPath, shellQuote(blueutilPath()))
	local output, success = hs.execute(command, true)
	if success ~= true then
		log("warn", string.format("blueutil 读取电源状态失败: success=%s output=%s", tostring(success), compactOutput(output)))
		return nil
	end

	local power = tonumber((output or ""):match("%d+"))
	if power == 0 or power == 1 then
		log("info", string.format("blueutil 电源状态: raw=%s parsed=%s", compactOutput(output), tostring(power)))
		return power
	end

	log("warn", "blueutil 电源状态无法解析: raw=" .. compactOutput(output))
	return nil
end

-- 设置蓝牙电源状态。
-- 入参：state 目标状态，支持 "on" 或 "0"。
-- 返回值：布尔值，true 表示命令执行成功。
function M.setPower(state)
	if not M.available() then
		return false
	end

	local command = string.format("%s %s --power %s >/dev/null 2>&1", shellPath, shellQuote(blueutilPath()), shellQuote(state))
	local _, success = hs.execute(command, true)
	if success == true then
		log("info", "blueutil 电源状态设置成功: " .. tostring(state))
	else
		log("warn", "blueutil 电源状态设置失败: " .. tostring(state))
	end
	return success == true
end

-- 关闭蓝牙。
-- 入参：无。
-- 返回值：布尔值，true 表示命令执行成功。
function M.powerOff()
	return M.setPower("0")
end

-- 开启蓝牙。
-- 入参：无。
-- 返回值：布尔值，true 表示命令执行成功。
function M.powerOn()
	return M.setPower("on")
end

return M
