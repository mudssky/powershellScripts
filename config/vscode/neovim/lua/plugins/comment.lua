-- -----------------------------------------------------------------------------
-- 文件: plugins/comment.lua
-- 描述: Comment.nvim 智能注释插件配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

return {
	"numToStr/Comment.nvim",
	event = "VeryLazy",
	opts = {},
	keys = {
		{ "gcc", desc = "Comment line" },
		{ "gc", mode = "v", desc = "Comment selection" },
	},
}
