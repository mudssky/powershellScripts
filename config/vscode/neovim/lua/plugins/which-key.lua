-- -----------------------------------------------------------------------------
-- 文件: plugins/which-key.lua
-- 描述: which-key.nvim 键位提示插件配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

local utils = require("utils")

return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	cond = not utils.is_vscode(),
	config = function()
		local wk = require("which-key")
		wk.setup({
			-- 配置选项
		})

		-- 键位映射
		wk.register({
			["<leader>f"] = { name = "查找" },
			["<leader>g"] = { name = "Git" },
			["<leader>l"] = { name = "LSP" },
			["<leader>t"] = { name = "终端" },
			["<leader>w"] = { name = "窗口" },
		})
	end,
}
