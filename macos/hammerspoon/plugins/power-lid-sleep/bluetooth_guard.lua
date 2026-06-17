-- 蓝牙休眠保护模块。
-- 功能：在合盖电池场景关闭蓝牙，并按需恢复原状态。
-- 入参：无；模块函数由 power-lid-sleep 插件入口调用。
-- 返回值：模块表。

local M = {}
local cachedBlueutilPath = nil

-- 查找 blueutil 可执行文件。
-- 入参：无。
-- 返回值：成功时返回可执行文件路径；失败时返回 nil。
local function blueutilPath()
	if cachedBlueutilPath ~= nil then
		return cachedBlueutilPath
	end

	local output = hs.execute([[PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" command -v blueutil 2>/dev/null]], true)
	if not output or output == "" then
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

	local command = string.format("%q --power 2>/dev/null", blueutilPath())
	local output = hs.execute(command, true)
	return tonumber(output)
end

-- 设置蓝牙电源状态。
-- 入参：state 目标状态，支持 "on" 或 "0"。
-- 返回值：布尔值，true 表示命令执行成功。
function M.setPower(state)
	if not M.available() then
		return false
	end

	local command = string.format("%q --power %s >/dev/null 2>&1", blueutilPath(), state)
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
