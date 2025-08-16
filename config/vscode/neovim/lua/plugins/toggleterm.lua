-- -----------------------------------------------------------------------------
-- 文件: plugins/toggleterm.lua
-- 描述: toggleterm.nvim 终端切换插件配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

local utils = require("utils")

return {
	"akinsho/toggleterm.nvim",
	version = "*",
	config = true,
	cond = not utils.is_vscode(),
}
