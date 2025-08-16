-- -----------------------------------------------------------------------------
-- 文件: plugins/bufferline.lua
-- 描述: 缓冲区标签栏配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

local utils = require("utils")

return {
	-- 缓冲区标签栏
	{
		"akinsho/bufferline.nvim",
		version = "*",
		cond = not utils.is_vscode(),
		dependencies = "nvim-tree/nvim-web-devicons",
		config = function()
			vim.opt.termguicolors = true -- 启用真彩色，对于主题显示很重要
			require("bufferline").setup({
				options = {
					-- 使用斜线分隔符 "slant" | "thick" | "thin" | { 'any', 'any' }
					separator_style = "slant",
					-- 鼠标点击切换 buffer
					mode = "buffers",
					-- 左侧的偏移量，以便为 nvim-tree 这样的插件留出空间
					offsets = {
						{
							filetype = "NvimTree",
							text = "File Explorer",
							text_align = "left",
							separator = true,
						},
					},
					-- 仅显示当前 buffer 的诊断信息
					diagnostics = "nvim_lsp",
					diagnostics_indicator = function(count, level, diagnostics_dict, context)
						local icon = level:match("error") and " " or (level:match("warning") and " " or " ")
						return " " .. icon .. count
					end,
					-- 在 bufferline 中显示 buffer 的编号
					numbers = "buffer_id",
					-- 悬停时显示完整路径
					hover = {
						enabled = true,
						delay = 200,
						reveal = { "close" },
					},
				},
			})
		end,
	},
}
