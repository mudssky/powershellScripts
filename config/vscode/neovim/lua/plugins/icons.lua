-- -----------------------------------------------------------------------------
-- 文件: plugins/icons.lua
-- 描述: 图标支持插件配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

local utils = require("utils")

return {
	-- 图标支持
	{
		"echasnovski/mini.icons",
		version = false, -- 使用最新版本
		cond = not utils.is_vscode(),
		config = function()
			require("mini.icons").setup({
				-- 使用默认配置
				style = "glyph", -- 可选: 'glyph' (default), 'ascii'
			})
			-- 确保与 nvim-web-devicons 兼容
			MiniIcons.mock_nvim_web_devicons()
		end,
	},
}
