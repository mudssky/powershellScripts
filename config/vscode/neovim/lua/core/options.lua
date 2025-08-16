-- -----------------------------------------------------------------------------
-- 文件: core/options.lua
-- 描述: Neovim 基础选项配置
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

-- 定义配置对象
local M = {}

-- 配置选项
M.config = {
	-- 只在vscode中生效
	onlyWorkInVscode = false,
	isVscodeEnv = vim.g.vscode,
}

-- 设置基础选项
function M.setup()
	-- VSCode 环境检测
	if (not M.config.isVscodeEnv) and M.config.onlyWorkInVscode then
		-- 如果不在 VSCode 环境中，则不加载此配置
		vim.notify("当前环境不是 VSCode，不加载配置", vim.log.levels.INFO, {
			title = "配置状态",
			timeout = 2000,
		})
		return
	end

	-- 配置加载成功提示
	vim.defer_fn(function()
		local message = M.config.isVscodeEnv and "✅ VSCode Neovim 配置已成功加载！"
			or "✅ Neovim 配置已成功加载！"
		vim.notify(message, vim.log.levels.INFO, {
			title = "配置状态",
			timeout = 3000,
		})
	end, 100)

	-- leader键设置
	-- 注意: 必须在加载插件之前设置
	-- 默认leader 键为\，所以不用配
	-- vim.g.mapleader = '\\'
	-- vim.g.maplocalleader  = '\\'
	-- vscode环境用which key插件，非vscode我们用空格
	if not M.config.isVscodeEnv then
		-- 设置 leader 键
		vim.g.mapleader = " "
		vim.g.maplocalleader = " "
	end

	-- 基础 Vim/Neovim 选项
	vim.opt.clipboard = "unnamedplus" -- 对应 "vim.useSystemClipboard": true (使用系统剪贴板)
	vim.opt.hlsearch = true -- 对应 "vim.hlsearch": true (高亮所有搜索项)
	vim.opt.incsearch = true -- 对应 "vim.incsearch": true (输入时即时搜索)
	vim.opt.ignorecase = true -- 搜索时忽略大小写
	vim.opt.smartcase = true -- 如果搜索词包含大写字母，则不忽略大小写
	vim.opt.wrap = false -- 关闭自动换行

	-- =============================================
	-- 根据操作系统自动配置 Shell
	-- =============================================

	if vim.fn.has("win32") then
		-- Windows 系统
		-- 使用 PowerShell 作为默认 Shell
		vim.opt.shell = "pwsh"

		-- 重要的！为 PowerShell 配置正确的参数，否则 :! 命令会出问题
		vim.opt.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy Bypass -Command "
		vim.opt.shellredir = "-join string | Out-File -Encoding utf8 %s"
		vim.opt.shellpipe = "2>&1 | %s"
		vim.opt.shellquote = ""
		vim.opt.shellxquote = ""
	elseif vim.fn.has("macunix") then
		-- macOS 系统
		-- zsh 是现代 macOS 的默认 shell
		vim.opt.shell = "zsh"
	elseif vim.fn.has("unix") then
		-- Linux 及其他 Unix-like 系统
		-- bash 是一个非常安全和普遍的默认选择
		vim.opt.shell = "bash"
	end
end

-- 导出配置对象供其他模块使用
M.get_config = function()
	return M.config
end

return M
