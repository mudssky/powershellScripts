-- -----------------------------------------------------------------------------
-- 文件: plugins/indent.lua
-- 描述: 缩进线配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

local utils = require("utils")

return {
	-- 缩进线
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		cond = not utils.is_vscode(),
		config = function()
			require("ibl").setup({
				indent = {
					char = "│",
					tab_char = "│",
				},
				scope = { enabled = false },
				exclude = {
					filetypes = {
						"help",
						"alpha",
						"dashboard",
						"neo-tree",
						"Trouble",
						"trouble",
						"lazy",
						"mason",
						"notify",
						"toggleterm",
						"lazyterm",
					},
				},
			})
		end,
	},
}
