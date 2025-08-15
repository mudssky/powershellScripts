-- -----------------------------------------------------------------------------
-- 文件: plugins/flash.lua
-- 描述: flash.nvim 快速跳转插件配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

return {
	"folke/flash.nvim",
	event = "VeryLazy",
	opts = {
		modes = {
			char = {
				enabled = true,
				jump_labels = true,
			},
		},
	},
	keys = {
		{
			"s",
			mode = { "n", "x", "o" },
			function()
				require("flash").jump()
			end,
			desc = "Flash Jump",
		},
		{
			"S",
			mode = { "n", "x", "o" },
			function()
				require("flash").treesitter()
			end,
			desc = "Flash Treesitter",
		},
		-- { "r",     mode = "o",               function() require("flash").remote() end,            desc = "Remote Flash" },
		-- { "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
		-- { "<c-s>", mode = { "c" },           function() require("flash").toggle() end,            desc = "Toggle Flash Search" },
	},
}
