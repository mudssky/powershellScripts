-- -----------------------------------------------------------------------------
-- 文件: plugins/ui.lua
-- 描述: UI/UX 增强插件配置
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

	-- 状态栏
	{
		"nvim-lualine/lualine.nvim",
		cond = not utils.is_vscode(),
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("lualine").setup({
				options = {
					theme = "auto", -- 自动匹配主题
					component_separators = { left = "", right = "" },
					section_separators = { left = "", right = "" },
					disabled_filetypes = {
						statusline = {},
						winbar = {},
					},
					ignore_focus = {},
					always_divide_middle = true,
					globalstatus = false,
					refresh = {
						statusline = 1000,
						tabline = 1000,
						winbar = 1000,
					},
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch", "diff", "diagnostics" },
					lualine_c = { "filename" },
					lualine_x = { "encoding", "fileformat", "filetype" },
					lualine_y = { "progress" },
					lualine_z = { "location" },
				},
				inactive_sections = {
					lualine_a = {},
					lualine_b = {},
					lualine_c = { "filename" },
					lualine_x = { "location" },
					lualine_y = {},
					lualine_z = {},
				},
				tabline = {},
				winbar = {},
				inactive_winbar = {},
				extensions = {},
			})
		end,
	},

	-- 缓冲区标签栏
	{
		"akinsho/bufferline.nvim",
		version = "*",
		cond = not utils.is_vscode(),
		dependencies = "nvim-tree/nvim-web-devicons",
		config = function()
			require("bufferline").setup({
				options = {
					mode = "buffers", -- set to "tabs" to only show tabpages instead
					style_preset = require("bufferline").style_preset.default, -- or bufferline.style_preset.minimal,
					themable = true,
					numbers = "none",
					close_command = "bdelete! %d", -- can be a string | function, | false see "Mouse actions"
					right_mouse_command = "bdelete! %d", -- can be a string | function | false, see "Mouse actions"
					left_mouse_command = "buffer %d", -- can be a string | function, | false see "Mouse actions"
					middle_mouse_command = nil, -- can be a string | function, | false see "Mouse actions"
					indicator = {
						icon = "▎", -- this should be omitted if indicator style is not 'icon'
						style = "icon",
					},
					buffer_close_icon = "󰅖",
					modified_icon = "●",
					close_icon = "",
					left_trunc_marker = "",
					right_trunc_marker = "",
					diagnostics = "nvim_lsp",
					diagnostics_update_in_insert = false,
					offsets = {
						{
							filetype = "NvimTree",
							text = "File Explorer",
							text_align = "left",
							separator = true,
						},
					},
					color_icons = true,
					show_buffer_icons = true,
					show_buffer_close_icons = true,
					show_close_icon = true,
					show_tab_indicators = true,
					show_duplicate_prefix = true,
					persist_buffer_sort = true,
					separator_style = "slant",
					enforce_regular_tabs = false,
					always_show_bufferline = true,
					hover = {
						enabled = true,
						delay = 200,
						reveal = { "close" },
					},
					sort_by = "insert_after_current",
				},
			})

			-- 添加缓冲区导航快捷键
			vim.keymap.set("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev Buffer" })
			vim.keymap.set("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })
			vim.keymap.set("n", "[b", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev Buffer" })
			vim.keymap.set("n", "]b", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })
			vim.keymap.set("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete Buffer" })
		end,
	},

	-- 文件树
	{
		"nvim-tree/nvim-tree.lua",
		cond = not utils.is_vscode(),
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			-- 禁用 netrw
			vim.g.loaded_netrw = 1
			vim.g.loaded_netrwPlugin = 1

			require("nvim-tree").setup({
				sort_by = "case_sensitive",
				view = {
					width = 30,
				},
				renderer = {
					group_empty = true,
					icons = {
						glyphs = {
							default = "",
							symlink = "",
							bookmark = "󰆤",
							modified = "●",
							folder = {
								arrow_closed = "",
								arrow_open = "",
								default = "",
								open = "",
								empty = "",
								empty_open = "",
								symlink = "",
								symlink_open = "",
							},
							git = {
								unstaged = "✗",
								staged = "✓",
								unmerged = "",
								renamed = "➜",
								untracked = "★",
								deleted = "",
								ignored = "◌",
							},
						},
					},
				},
				filters = {
					dotfiles = false,
				},
				git = {
					enable = true,
					ignore = false,
					timeout = 400,
				},
				actions = {
					use_system_clipboard = true,
					change_dir = {
						enable = true,
						global = false,
						restrict_above_cwd = false,
					},
					expand_all = {
						max_folder_discovery = 300,
						exclude = {},
					},
					file_popup = {
						open_win_config = {
							col = 1,
							row = 1,
							relative = "cursor",
							border = "shadow",
							style = "minimal",
						},
					},
					open_file = {
						quit_on_open = false,
						resize_window = true,
						window_picker = {
							enable = true,
							picker = "default",
							chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890",
							exclude = {
								filetype = { "notify", "packer", "qf", "diff", "fugitive", "fugitiveblame" },
								buftype = { "nofile", "terminal", "help" },
							},
						},
					},
					remove_file = {
						close_window = true,
					},
				},
				notify = {
					threshold = vim.log.levels.INFO,
				},
				log = {
					enable = false,
					truncate = false,
					types = {
						all = false,
						config = false,
						copy_paste = false,
						dev = false,
						diagnostics = false,
						git = false,
						profile = false,
						watcher = false,
					},
				},
			})

			-- 添加文件树快捷键
			vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle NvimTree" })
			vim.keymap.set("n", "<leader>o", "<cmd>NvimTreeFocus<CR>", { desc = "Focus NvimTree" })
		end,
	},

	-- 通知增强
	{
		"rcarriga/nvim-notify",
		version = "*", -- 使用最新稳定版本以确保兼容性
		cond = not utils.is_vscode(),
		config = function()
			-- 检查 Neovim 版本兼容性
			local notify_config = {
				background_colour = "NotifyBackground",
				fps = 30,
				icons = {
					DEBUG = "",
					ERROR = "",
					INFO = "",
					TRACE = "✎",
					WARN = "",
				},
				level = 2,
				minimum_width = 50,
				render = "default",
				stages = "fade_in_slide_out",
				timeout = 5000,
				top_down = true,
			}

			-- 安全地设置 nvim-notify
			local ok, notify = pcall(require, "notify")
			if ok then
				notify.setup(notify_config)
				vim.notify = notify
			else
				vim.notify("Failed to load nvim-notify", vim.log.levels.WARN)
			end
		end,
	},

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
