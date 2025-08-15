-- -----------------------------------------------------------------------------
-- 文件: init.lua
-- 描述: 用于 VSCode Neovim 的配置
-- -----------------------------------------------------------------------------

-- 1. leader键设置
-- 注意: 必须在加载插件之前设置
-- 默认leader 键为\，所以不用配
-- vim.g.mapleader = '\\'
-- vim.g.maplocalleader  = '\\'

-- 2. 基础 Vim/Neovim 选项
vim.opt.clipboard = 'unnamedplus'  -- 对应 "vim.useSystemClipboard": true (使用系统剪贴板)
vim.opt.hlsearch = true           -- 对应 "vim.hlsearch": true (高亮所有搜索项)
vim.opt.incsearch = true          -- 对应 "vim.incsearch": true (输入时即时搜索)
vim.opt.ignorecase = true         -- 搜索时忽略大小写
vim.opt.smartcase = true          -- 如果搜索词包含大写字母，则不忽略大小写
vim.opt.wrap = false              -- 关闭自动换行


-- 3. 插件管理 (使用 lazy.nvim)
-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)


-- Setup lazy.nvim
require("lazy").setup({
    spec = {
      -- 插件列表
      {
        -- 对应 "vim.easymotion": true。flash.nvim 是更现代化的选择
        'folke/flash.nvim',
        event = 'VeryLazy',
        opts = {},
        -- (可选) 如果你还想用 easymotion 的经典按键
        keys = {
          { 's', mode = { 'n', 'x', 'o' }, function() require('flash').jump() end, desc = 'Flash Jump' },
        },
      },
      {
        -- 对应 "vim.replaceWithRegister": true
        'vim-scripts/ReplaceWithRegister',
      },
    },
    -- Configure any other settings here. See the documentation for more details.
    -- colorscheme that will be used when installing plugins.
    install = { colorscheme = { "habamax" } },
    -- automatically check for plugin updates
    checker = { enabled = true },
  })


-- 4. 键位映射 (Keymaps)
local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

-- 插入模式
-- 对应 "before": ["j", "j"], "after": ["<Esc>"]
keymap('i', 'jj', '<Esc>', opts)

-- 普通模式
-- 对应 "<leader>n" 取消高亮
keymap('n', '<leader>n', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlight' })

-- 调用vscode命令
-- 对应 "<space>" 触发 which-key (这是与 VSCode 交互的关键)
-- 我们通过 Neovim 调用 VSCode 的命令
keymap('n', '<space>', function()
    require('vscode').action('whichkey.show')
  end, { noremap = true, silent = true, desc = 'Show WhichKey' })

-- 书签相关功能 (同样是调用 VSCode 命令)
keymap('n', '<leader>bt', function()
    require('vscode').action('bookmarks.toggle')
  end, { noremap = true, silent = true, desc = 'Toggle Bookmark' })

keymap('n', '<leader>bl', function()
    require('vscode').action('bookmarks.listFromAllFiles')
  end, { noremap = true, silent = true, desc = 'List Bookmarks' })

-- 可视模式
-- 对应 "<space>" 触发 which-key
keymap('v', '<space>', function()
    require('vscode').action('whichkey.show')
  end, { noremap = true, silent = true, desc = 'Show WhichKey' })

-- 对应 ">" 和 "<" 调整缩进
-- Neovim 在可视模式下默认就有这个功能，但为了保证选中状态，可以这样映射
keymap('v', '>', '>gv', opts)
keymap('v', '<', '<gv', opts)