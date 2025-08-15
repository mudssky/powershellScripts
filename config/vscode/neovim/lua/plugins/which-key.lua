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

		-- 注册键位映射组 (新格式)
		wk.add({
			{ "<leader>f", group = "查找" },
			{ "<leader>g", group = "Git" },
			{ "<leader>l", group = "LSP" },
			{ "<leader>s", group = "包围符号" },
			{ "<leader>t", group = "终端" },
			{ "<leader>w", group = "窗口" },
			{ "<leader>c", group = "代码" },
			{ "<leader>b", group = "缓冲区" },
		})
	end,
}
