-- -----------------------------------------------------------------------------
-- 文件: core/keymaps.lua
-- 描述: 键位映射配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

local M = {}
local utils = require("utils")

-- 设置键位映射
function M.setup()
	local keymap = vim.keymap.set
	local opts = { noremap = true, silent = true }

	-- =============================================
	-- 基础键位映射
	-- =============================================

	-- 插入模式
	-- 快速退出插入模式
	keymap("i", "jj", "<Esc>", opts)

	-- 普通模式
	-- 取消搜索高亮
	keymap("n", "<leader>n", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

	-- 更好的行移动（处理自动换行的情况）
	keymap("n", "j", "gj", opts)
	keymap("n", "k", "gk", opts)

	-- 窗口导航
	keymap("n", "<C-h>", "<C-w>h", opts)
	keymap("n", "<C-j>", "<C-w>j", opts)
	keymap("n", "<C-k>", "<C-w>k", opts)
	keymap("n", "<C-l>", "<C-w>l", opts)

	-- 可视模式
	-- 保持缩进选择
	keymap("v", ">", ">gv", opts)
	keymap("v", "<", "<gv", opts)

	-- 移动选中的行
	keymap("v", "J", ":m '>+1<CR>gv=gv", opts)
	keymap("v", "K", ":m '<-2<CR>gv=gv", opts)

	-- =============================================
	-- VSCode 集成键位映射
	-- =============================================

	-- 只在 VSCode 环境中设置 VSCode 特定的键位映射
	if utils.is_vscode() then
		M.setup_vscode_keymaps()
	else
		M.setup_neovim_keymaps()
	end
end

-- VSCode 环境键位映射
function M.setup_vscode_keymaps()
	local keymap = vim.keymap.set
	local vscode = utils.vscode

	-- WhichKey 集成
	keymap("n", "<space>", vscode("whichkey.show"), { desc = "Show WhichKey" })
	keymap("v", "<space>", vscode("whichkey.show"), { desc = "Show WhichKey" })

	-- 文件操作
	keymap("n", "<leader>w", vscode("workbench.action.files.save"), { desc = "Save File" })
	keymap("n", "<leader>ff", vscode("workbench.action.quickOpen"), { desc = "Find Files" })
	keymap("n", "<leader>fg", vscode("workbench.action.findInFiles"), { desc = "Find in Files" })
	keymap("n", "<leader>fs", vscode("workbench.action.gotoSymbol"), { desc = "Find Symbols" })

	-- 编辑器操作
	keymap("n", "<leader>e", vscode("workbench.view.explorer"), { desc = "Toggle Explorer" })
	keymap("n", "<leader>g", vscode("workbench.view.scm"), { desc = "Toggle Git" })
	keymap("n", "<leader>x", vscode("workbench.view.extensions"), { desc = "Toggle Extensions" })

	-- 代码操作
	keymap("n", "<leader>ca", vscode("editor.action.quickFix"), { desc = "Code Action" })
	keymap("n", "<leader>cr", vscode("editor.action.rename"), { desc = "Rename Symbol" })
	keymap("n", "<leader>cf", vscode("editor.action.formatDocument"), { desc = "Format Document" })
	keymap("n", "gd", vscode("editor.action.revealDefinition"), { desc = "Go to Definition" })
	keymap("n", "gr", vscode("editor.action.goToReferences"), { desc = "Go to References" })
	keymap("n", "gi", vscode("editor.action.goToImplementation"), { desc = "Go to Implementation" })

	-- 书签相关功能
	keymap("n", "<leader>bt", vscode("bookmarks.toggle"), { desc = "Toggle Bookmark" })
	keymap("n", "<leader>bl", vscode("bookmarks.listFromAllFiles"), { desc = "List Bookmarks" })

	-- 终端操作
	keymap("n", "<leader>t", vscode("workbench.action.terminal.toggleTerminal"), { desc = "Toggle Terminal" })

	-- 面板操作
	keymap("n", "<leader>p", vscode("workbench.action.togglePanel"), { desc = "Toggle Panel" })

	-- 注释操作（使用 Comment.nvim 插件，但也提供 VSCode 命令作为备选）
	keymap("n", "<leader>/", vscode("editor.action.commentLine"), { desc = "Toggle Comment" })
	keymap("v", "<leader>/", vscode("editor.action.commentLine"), { desc = "Toggle Comment" })
end

-- 普通 Neovim 环境键位映射
function M.setup_neovim_keymaps()
	local keymap = vim.keymap.set

	-- 文件操作 - 使用 Neovim 内置功能
	keymap("n", "<leader>w", "<cmd>write<CR>", { desc = "Save File" })

	-- 尝试加载 Telescope 并设置键位映射
	local has_telescope, telescope_builtin = pcall(require, "telescope.builtin")
	if has_telescope then
		-- Telescope 文件和搜索功能
		keymap("n", "<leader>ff", telescope_builtin.find_files, { desc = "Find Files" })
		keymap("n", "<leader>fg", telescope_builtin.live_grep, { desc = "Find in Files" })
		keymap("n", "<leader>fs", telescope_builtin.lsp_document_symbols, { desc = "Find Symbols" })
		keymap("n", "<leader>fb", telescope_builtin.buffers, { desc = "Find Buffers" })
		keymap("n", "<leader>fh", telescope_builtin.help_tags, { desc = "Find Help" })
		keymap("n", "<leader>fr", telescope_builtin.oldfiles, { desc = "Recent Files" })
		keymap("n", "gr", telescope_builtin.lsp_references, { desc = "Go to References" })
	else
		-- 如果 Telescope 不可用，使用基本的 Neovim 命令
		keymap("n", "<leader>ff", "<cmd>find<CR>", { desc = "Find Files" })
		keymap("n", "gr", vim.lsp.buf.references, { desc = "Go to References" })
	end

	-- 代码操作 - 使用 LSP 功能（如果可用）
	keymap("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code Action" })
	keymap("n", "<leader>cr", vim.lsp.buf.rename, { desc = "Rename Symbol" })
	keymap("n", "<leader>cf", vim.lsp.buf.format, { desc = "Format Document" })
	keymap("n", "gd", vim.lsp.buf.definition, { desc = "Go to Definition" })
	keymap("n", "gi", vim.lsp.buf.implementation, { desc = "Go to Implementation" })

	-- 终端操作
	keymap("n", "<leader>t", "<cmd>terminal<CR>", { desc = "Open Terminal" })
end

return M
