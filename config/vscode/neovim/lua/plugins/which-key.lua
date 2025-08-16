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
		-- 设置 Neovim 的 timeoutlen，对于 which-key 至关重要
		vim.o.timeout = true
		vim.o.timeoutlen = 300

		wk.setup({
			-- 窗口和布局配置
			-- win = {
			-- 	border = "rounded", -- 窗口边框样式
			-- 	padding = { 1, 2 }, -- 窗口内边距
			-- },
			-- 禁用内置插件提示，让界面更干净 (可按需开启)
			-- plugins = {
			-- 	marks = false,
			-- 	registers = false,
			-- 	spelling = {
			-- 		enabled = false,
			-- 	},
			-- 	presets = {
			-- 		operators = false,
			-- 		motions = false,
			-- 		text_objects = false,
			-- 		windows = false,
			-- 		nav = false,
			-- 		z = false,
			-- 		g = false,
			-- 	},
			-- }
		})

		-- 注册键位映射组
		wk.add({
			{ "<leader>f", group = "Find" },
			{ "<leader>g", group = "Git" },
			{ "<leader>l", group = "LSP" },
			{ "<leader>s", group = "Search/Surround" },
			{ "<leader>t", group = "Terminal" },
			{ "<leader>w", group = "Window" },
			{ "<leader>c", group = "Code" },
			{ "<leader>b", group = "Buffer" },
		})
		-- 因为是 whichkey相关快捷键，所以直接加这里
		vim.keymap.set("n", "<leader>?", function()
			require("which-key").show({ global = false })
		end, { desc = "Buffer Local Keymaps (which-key)" })
	end,
}
