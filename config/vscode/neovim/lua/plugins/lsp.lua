-- -----------------------------------------------------------------------------
-- 文件: plugins/lsp.lua
-- 描述: LSP 配置和自动补全设置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

local utils = require("utils")

return {
	-- LSP 配置
	{
		"neovim/nvim-lspconfig",
		cond = not utils.is_vscode(),
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			-- 自动安装LSP
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",

			-- 自动补全引擎
			"hrsh7th/nvim-cmp",
			"hrsh7th/cmp-nvim-lsp", -- LSP 补全源
			"hrsh7th/cmp-buffer", -- Buffer 补全源
			"hrsh7th/cmp-path", -- 路径补全源

			-- 代码片段引擎
			"L3MON4D3/LuaSnip",
			"saadparwaiz1/cmp_luasnip",
		},
		config = function()
			-- 只有在非 VSCode 环境下才执行配置
			if utils.is_vscode() then
				return
			end

			local lspconfig = require("lspconfig")
			local cmp = require("cmp")
			local capabilities = require("cmp_nvim_lsp").default_capabilities()

			-- Mason 设置
			require("mason").setup({
				ui = {
					icons = {
						package_installed = "✓",
						package_pending = "➜",
						package_uninstalled = "✗",
					},
				},
			})

			require("mason-lspconfig").setup({
				-- 确保你需要的 LSP 已经被 mason-lspconfig 安装
				ensure_installed = {
					"lua_ls",
					"tsserver",
					"pyright",
					"gopls",
					"rust_analyzer",
					"jsonls",
					"yamlls",
				},
				handlers = {
					function(server_name) -- 默认设置
						lspconfig[server_name].setup({
							capabilities = capabilities,
						})
					end,
					-- 为 lua_ls 添加特殊设置
					["lua_ls"] = function()
						lspconfig.lua_ls.setup({
							capabilities = capabilities,
							settings = {
								Lua = {
									diagnostics = {
										globals = { "vim" },
									},
									workspace = {
										library = vim.api.nvim_get_runtime_file("", true),
									},
									telemetry = {
										enable = false,
									},
								},
							},
						})
					end,
				},
			})

			-- Nvim-cmp 设置
			cmp.setup({
				snippet = {
					expand = function(args)
						require("luasnip").lsp_expand(args.body)
					end,
				},
				mapping = cmp.mapping.preset.insert({
					["<C-b>"] = cmp.mapping.scroll_docs(-4),
					["<C-f>"] = cmp.mapping.scroll_docs(4),
					["<C-Space>"] = cmp.mapping.complete(),
					["<C-e>"] = cmp.mapping.abort(),
					["<CR>"] = cmp.mapping.confirm({ select = true }),
					["<Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_next_item()
						else
							fallback()
						end
					end, { "i", "s" }),
					["<S-Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_prev_item()
						else
							fallback()
						end
					end, { "i", "s" }),
				}),
				sources = cmp.config.sources({
					{ name = "nvim_lsp" },
					{ name = "luasnip" },
				}, {
					{ name = "buffer" },
					{ name = "path" },
				}),
				formatting = {
					format = function(entry, vim_item)
						-- 设置补全项的图标
						local kind_icons = {
							Text = "",
							Method = "󰆧",
							Function = "󰊕",
							Constructor = "",
							Field = "󰇽",
							Variable = "󰂡",
							Class = "󰠱",
							Interface = "",
							Module = "",
							Property = "󰜢",
							Unit = "󰑭",
							Value = "󰎠",
							Enum = "",
							Keyword = "󰌋",
							Snippet = "",
							Color = "󰏘",
							File = "󰈙",
							Reference = "",
							Folder = "󰉋",
							EnumMember = "",
							Constant = "󰏿",
							Struct = "",
							Event = "",
							Operator = "󰆕",
							TypeParameter = "󰅲",
						}
						vim_item.kind = string.format("%s %s", kind_icons[vim_item.kind], vim_item.kind)
						vim_item.menu = ({
							nvim_lsp = "[LSP]",
							luasnip = "[Snippet]",
							buffer = "[Buffer]",
							path = "[Path]",
						})[entry.source.name]
						return vim_item
					end,
				},
			})
		end,
	},
}
