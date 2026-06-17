-- 合盖状态检测模块。
-- 功能：封装 MacBook 合盖能力检测与当前合盖状态读取。
-- 入参：无；模块函数通过 hs.execute 调用系统命令。
-- 返回值：模块表。

local M = {}

-- 读取 AppleClamshellState 原始输出。
-- 入参：无。
-- 返回值：成功时返回字符串；失败时返回 nil。
local function readClamshellState()
	local output = hs.execute([[ioreg -r -k AppleClamshellState -d 1 | awk -F'= ' '/AppleClamshellState/ {print $2; exit}']], true)
	if not output or output == "" then
		return nil
	end

	return output:gsub("%s+", "")
end

-- 判断当前设备是否支持合盖状态。
-- 入参：无。
-- 返回值：布尔值，true 表示可读取 AppleClamshellState。
function M.supportsClamshell()
	return readClamshellState() ~= nil
end

-- 判断当前是否合盖。
-- 入参：无。
-- 返回值：布尔值，true 表示已合盖。
function M.isClosed()
	local state = readClamshellState()
	return state == "Yes"
end

-- 获取硬件型号，用于日志诊断。
-- 入参：无。
-- 返回值：硬件型号字符串；读取失败时返回 unknown。
function M.hardwareModel()
	local output = hs.execute([[sysctl -n hw.model 2>/dev/null]], true)
	if not output or output == "" then
		return "unknown"
	end

	return output:gsub("%s+", "")
end

return M
