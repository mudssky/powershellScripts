-- -----------------------------------------------------------------------------
-- 文件: plugins/notify.lua
-- 描述: 通知增强配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

local utils = require("utils")

return {
	-- 通知增强
	{
		"rcarriga/nvim-notify",
		version = "*", -- 使用最新稳定版本以确保兼容性
		cond = not utils.is_vscode(),
		config = function()
			-- 检查 Neovim 版本兼容性
			local notify_config = {
				background_colour = "NotifyBackground",
				fps = 30,
				icons = {
					DEBUG = "",
					ERROR = "",
					INFO = "",
					TRACE = "✎",
					WARN = "",
				},
				level = 2,
				minimum_width = 50,
				render = "default",
				stages = "fade_in_slide_out",
				timeout = 5000,
				top_down = true,
			}

			-- 安全地设置 nvim-notify
			local ok, notify = pcall(require, "notify")
			if ok then
				notify.setup(notify_config)
				vim.notify = notify
			else
				vim.notify("Failed to load nvim-notify", vim.log.levels.WARN)
			end
		end,
	},
}
