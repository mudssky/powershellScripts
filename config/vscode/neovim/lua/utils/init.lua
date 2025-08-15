-- -----------------------------------------------------------------------------
-- 文件: utils/init.lua
-- 描述: 通用工具函数
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

local M = {}

-- VSCode 命令调用辅助函数
-- 只在 VSCode 环境中可用
M.vscode = function(command)
	return function()
		if vim.g.vscode then
			require("vscode").action(command)
		else
			vim.notify("VSCode 命令只能在 VSCode 环境中使用: " .. command, vim.log.levels.WARN)
		end
	end
end

-- 检查是否在 VSCode 环境中
M.is_vscode = function()
	return vim.g.vscode ~= nil
end

-- 安全地尝试加载模块
M.safe_require = function(module)
	local ok, result = pcall(require, module)
	if not ok then
		vim.notify("无法加载模块: " .. module, vim.log.levels.ERROR)
		return nil
	end
	return result
end

-- 检查插件是否可用
M.has_plugin = function(plugin_name)
	local ok, _ = pcall(require, plugin_name)
	return ok
end

-- 加载插件配置
M.load_plugin_specs = function()
	-- 获取插件配置目录的绝对路径
	local config_path = vim.fn.fnamemodify(debug.getinfo(2, "S").source:sub(2), ":p:h:h")
	local plugins_path = config_path .. "/plugins"

	-- 手动加载所有插件配置
	local plugin_specs = {}
	local plugin_files = vim.fn.glob(plugins_path .. "/*.lua", false, true)

	for _, file in ipairs(plugin_files) do
		local plugin_name = vim.fn.fnamemodify(file, ":t:r")
		local ok, plugin_config = pcall(dofile, file)
		if ok and plugin_config then
			table.insert(plugin_specs, plugin_config)
		else
			vim.notify("Failed to load plugin: " .. plugin_name, vim.log.levels.WARN)
		end
	end

	return plugin_specs
end

return M
