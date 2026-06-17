-- 应用休眠保护模块。
-- 功能：检测会阻止休眠的应用是否空闲，并按配置退出空闲应用。
-- 入参：无；模块函数由 power-lid-sleep 插件入口调用。
-- 返回值：模块表。

local M = {}

-- 判断应用是否正在运行。
-- 入参：appConfig 应用配置表。
-- 返回值：布尔值，true 表示应用正在运行。
function M.isRunning(appConfig)
	return hs.application.get(appConfig.name) ~= nil
end

-- 读取应用活跃连接数量。
-- 入参：appConfig 应用配置表。
-- 返回值：数字，表示活跃连接数量。
function M.activeConnections(appConfig)
	if not appConfig.idleConnectionCommand or appConfig.idleConnectionCommand == "" then
		return 0
	end

	local output = hs.execute(appConfig.idleConnectionCommand, true)
	return tonumber(output) or 0
end

-- 退出指定应用。
-- 入参：appConfig 应用配置表；showAlert 是否显示提示。
-- 返回值：布尔值，true 表示已发起退出。
function M.quit(appConfig, showAlert)
	local app = hs.application.get(appConfig.name)
	if not app then
		return false
	end

	if showAlert ~= false then
		hs.alert.show(string.format("电池合盖且 %s 空闲，退出 %s", appConfig.name, appConfig.name))
	end

	app:kill()
	return true
end

return M
