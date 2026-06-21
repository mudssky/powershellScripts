-- 蓝牙休眠保护模块。
-- 功能：在合盖电池场景关闭蓝牙，并按需恢复原状态。
-- 入参：无；模块函数由 power-lid-sleep 插件入口调用。
-- 返回值：模块表。

local M = {}
local cachedBlueutilPath = nil
local shellPath = [[PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]]

-- 转义用于单引号 shell 字符串的文本。
-- 入参：value 原始文本。
-- 返回值：可安全放入单引号的文本。
local function shellQuote(value)
	return "'" .. tostring(value):gsub("'", [["'"']]) .. "'"
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
		return nil
	end

	cachedBlueutilPath = output:gsub("%s+", "")
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
		return nil
	end

	local power = tonumber((output or ""):match("%d+"))
	if power == 0 or power == 1 then
		return power
	end

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
