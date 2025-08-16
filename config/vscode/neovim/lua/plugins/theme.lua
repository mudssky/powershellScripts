-- -----------------------------------------------------------------------------
-- 文件: plugins/theme.lua
-- 描述: 主题配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

local utils = require("utils")

return {
	-- 主题
	{
		"folke/tokyonight.nvim",
		lazy = false,
		priority = 1000,
		cond = not utils.is_vscode(),
		config = function()
			-- 只有在非 VSCode 环境中才加载主题
			if not utils.is_vscode() then
				require("tokyonight").setup({
					style = "night", -- storm, moon, night, day
					transparent = false,
					terminal_colors = true,
					styles = {
						comments = { italic = true },
						keywords = { italic = true },
						functions = {},
						variables = {},
					},
				})
				vim.cmd.colorscheme("tokyonight")
			end
		end,
	},
}
