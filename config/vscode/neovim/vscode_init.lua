-- -----------------------------------------------------------------------------
-- 文件: vscode_init.lua
-- 描述: 兼容 VSCode Neovim 和普通 Neovim 的优化配置
--       在 VSCode 环境中提供 VSCode 集成功能
--       在普通 Neovim 环境中提供标准 LSP 和内置功能
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------
-- 定义空配置对象
local config = {
  -- 只在vscode中生效
  onlyWorkInVscode = false,
  isVscodeEnv = vim.g.vscode
}



-- VSCode 环境检测
if (not config.isVscodeEnv) and config.onlyWorkInVscode then
  -- 如果不在 VSCode 环境中，则不加载此配置
  vim.notify("当前环境不是 VSCode，不加载配置", vim.log.levels.INFO, {
    title = "配置状态",
    timeout = 2000,
  })
  return
end

-- 配置加载成功提示
vim.defer_fn(function()
  local message = config.isVscodeEnv and "✅ VSCode Neovim 配置已成功加载！" or "✅ Neovim 配置已成功加载！"
  vim.notify(message, vim.log.levels.INFO, {
    title = "配置状态",
    timeout = 3000,
  })
end, 100)

-- 1. leader键设置
-- 注意: 必须在加载插件之前设置
-- 默认leader 键为\，所以不用配
-- vim.g.mapleader = '\\'
-- vim.g.maplocalleader  = '\\'

-- 2. 基础 Vim/Neovim 选项
vim.opt.clipboard = 'unnamedplus' -- 对应 "vim.useSystemClipboard": true (使用系统剪贴板)
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
      { out,                            "WarningMsg" },
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
    -- 快速跳转插件
    {
      'folke/flash.nvim',
      event = 'VeryLazy',
      opts = {
        modes = {
          char = {
            enabled = true,
            jump_labels = true,
          },
        },
      },
      keys = {
        { 's', mode = { 'n', 'x', 'o' }, function() require('flash').jump() end,       desc = 'Flash Jump' },
        { 'S', mode = { 'n', 'x', 'o' }, function() require('flash').treesitter() end, desc = 'Flash Treesitter' },
        -- { "r",     mode = "o",               function() require("flash").remote() end,            desc = "Remote Flash" },
        -- { "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
        -- { "<c-s>", mode = { "c" },           function() require("flash").toggle() end,            desc = "Toggle Flash Search" },
      },
    },

    -- 文本替换插件
    {
      'vim-scripts/ReplaceWithRegister',
      keys = {
        { 'gr',  desc = 'Replace with register' },
        { 'grr', desc = 'Replace line with register' },
      },
    },

    -- 包围符号操作
    {
      'kylechui/nvim-surround',
      event = 'VeryLazy',
      opts = {},
    },

    -- 智能注释
    {
      'numToStr/Comment.nvim',
      event = 'VeryLazy',
      opts = {},
      keys = {
        { 'gcc', desc = 'Comment line' },
        { 'gc',  mode = 'v',           desc = 'Comment selection' },
      },
    },

    -- 增强的文本对象
    {
      'echasnovski/mini.ai',
      event = 'VeryLazy',
      opts = function()
        local ai = require('mini.ai')
        return {
          n_lines = 500,
          custom_textobjects = {
            o = ai.gen_spec.treesitter({
              a = { '@block.outer', '@conditional.outer', '@loop.outer' },
              i = { '@block.inner', '@conditional.inner', '@loop.inner' },
            }, {}),
            f = ai.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }, {}),
            c = ai.gen_spec.treesitter({ a = '@class.outer', i = '@class.inner' }, {}),
          },
        }
      end,
    },

    -- 键位提示（在非 VSCode 环境中更有用，VSCode 已有 WhichKey）
    {
      'folke/which-key.nvim',
      event = 'VeryLazy',
      cond = not config.isVscodeEnv, -- 只在非 VSCode 环境中加载
      opts = {
        plugins = { spelling = true },
        defaults = {},
      },
    },

    -- Telescope 模糊查找插件（主要用于非 VSCode 环境）
    {
      'nvim-telescope/telescope.nvim',
      tag = '0.1.8',
      cond = not config.isVscodeEnv, -- 只在非 VSCode 环境中加载
      dependencies = {
        'nvim-lua/plenary.nvim',
        {
          'nvim-telescope/telescope-fzf-native.nvim',
          build = 'make',
          cond = function()
            return vim.fn.executable 'make' == 1
          end,
        },
      },
      config = function()
        local telescope = require('telescope')
        local actions = require('telescope.actions')

        telescope.setup({
          defaults = {
            mappings = {
              i = {
                ['<C-k>'] = actions.move_selection_previous,
                ['<C-j>'] = actions.move_selection_next,
                ['<C-q>'] = actions.send_selected_to_qflist + actions.open_qflist,
              },
            },
          },
        })

        -- 加载 fzf 扩展（如果可用）
        pcall(telescope.load_extension, 'fzf')
      end,
    },
  },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = { colorscheme = { "habamax" } },
  -- automatically check for plugin updates
  checker = { enabled = true },
  -- 性能优化
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "matchit",
        "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})


-- 4. 键位映射 (Keymaps)
local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

-- =============================================
-- 基础键位映射
-- =============================================

-- 插入模式
-- 快速退出插入模式
keymap('i', 'jj', '<Esc>', opts)

-- 普通模式
-- 取消搜索高亮
keymap('n', '<leader>n', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlight' })

-- 更好的行移动（处理自动换行的情况）
keymap('n', 'j', 'gj', opts)
keymap('n', 'k', 'gk', opts)

-- 窗口导航
keymap('n', '<C-h>', '<C-w>h', opts)
keymap('n', '<C-j>', '<C-w>j', opts)
keymap('n', '<C-k>', '<C-w>k', opts)
keymap('n', '<C-l>', '<C-w>l', opts)

-- 可视模式
-- 保持缩进选择
keymap('v', '>', '>gv', opts)
keymap('v', '<', '<gv', opts)

-- 移动选中的行
keymap('v', 'J', ":m '>+1<CR>gv=gv", opts)
keymap('v', 'K', ":m '<-2<CR>gv=gv", opts)

-- =============================================
-- VSCode 集成键位映射
-- =============================================

-- 只在 VSCode 环境中设置 VSCode 特定的键位映射
if config.isVscodeEnv then
  -- 调用 VSCode 命令的辅助函数
  local function vscode(command)
    return function()
      require('vscode').action(command)
    end
  end

  -- WhichKey 集成
  keymap('n', '<space>', vscode('whichkey.show'), { desc = 'Show WhichKey' })
  keymap('v', '<space>', vscode('whichkey.show'), { desc = 'Show WhichKey' })

  -- 文件操作
  keymap('n', '<leader>w', vscode('workbench.action.files.save'), { desc = 'Save File' })
  keymap('n', '<leader>ff', vscode('workbench.action.quickOpen'), { desc = 'Find Files' })
  keymap('n', '<leader>fg', vscode('workbench.action.findInFiles'), { desc = 'Find in Files' })
  keymap('n', '<leader>fs', vscode('workbench.action.gotoSymbol'), { desc = 'Find Symbols' })

  -- 编辑器操作
  keymap('n', '<leader>e', vscode('workbench.view.explorer'), { desc = 'Toggle Explorer' })
  keymap('n', '<leader>g', vscode('workbench.view.scm'), { desc = 'Toggle Git' })
  keymap('n', '<leader>x', vscode('workbench.view.extensions'), { desc = 'Toggle Extensions' })

  -- 代码操作
  keymap('n', '<leader>ca', vscode('editor.action.quickFix'), { desc = 'Code Action' })
  keymap('n', '<leader>cr', vscode('editor.action.rename'), { desc = 'Rename Symbol' })
  keymap('n', '<leader>cf', vscode('editor.action.formatDocument'), { desc = 'Format Document' })
  keymap('n', 'gd', vscode('editor.action.revealDefinition'), { desc = 'Go to Definition' })
  keymap('n', 'gr', vscode('editor.action.goToReferences'), { desc = 'Go to References' })
  keymap('n', 'gi', vscode('editor.action.goToImplementation'), { desc = 'Go to Implementation' })

  -- 书签相关功能
  keymap('n', '<leader>bt', vscode('bookmarks.toggle'), { desc = 'Toggle Bookmark' })
  keymap('n', '<leader>bl', vscode('bookmarks.listFromAllFiles'), { desc = 'List Bookmarks' })

  -- 终端操作
  keymap('n', '<leader>t', vscode('workbench.action.terminal.toggleTerminal'), { desc = 'Toggle Terminal' })

  -- 面板操作
  keymap('n', '<leader>p', vscode('workbench.action.togglePanel'), { desc = 'Toggle Panel' })

  -- 注释操作（使用 Comment.nvim 插件，但也提供 VSCode 命令作为备选）
  keymap('n', '<leader>/', vscode('editor.action.commentLine'), { desc = 'Toggle Comment' })
  keymap('v', '<leader>/', vscode('editor.action.commentLine'), { desc = 'Toggle Comment' })
else
  -- 非 VSCode 环境的替代键位映射
  -- 文件操作 - 使用 Neovim 内置功能
  keymap('n', '<leader>w', '<cmd>write<CR>', { desc = 'Save File' })

  -- 尝试加载 Telescope 并设置键位映射
  local has_telescope, telescope_builtin = pcall(require, 'telescope.builtin')
  if has_telescope then
    -- Telescope 文件和搜索功能
    keymap('n', '<leader>ff', telescope_builtin.find_files, { desc = 'Find Files' })
    keymap('n', '<leader>fg', telescope_builtin.live_grep, { desc = 'Find in Files' })
    keymap('n', '<leader>fs', telescope_builtin.lsp_document_symbols, { desc = 'Find Symbols' })
    keymap('n', '<leader>fb', telescope_builtin.buffers, { desc = 'Find Buffers' })
    keymap('n', '<leader>fh', telescope_builtin.help_tags, { desc = 'Find Help' })
    keymap('n', '<leader>fr', telescope_builtin.oldfiles, { desc = 'Recent Files' })
    keymap('n', 'gr', telescope_builtin.lsp_references, { desc = 'Go to References' })
  else
    -- 如果 Telescope 不可用，使用基本的 Neovim 命令
    keymap('n', '<leader>ff', '<cmd>find<CR>', { desc = 'Find Files' })
    keymap('n', 'gr', vim.lsp.buf.references, { desc = 'Go to References' })
  end

  -- 代码操作 - 使用 LSP 功能（如果可用）
  keymap('n', '<leader>ca', vim.lsp.buf.code_action, { desc = 'Code Action' })
  keymap('n', '<leader>cr', vim.lsp.buf.rename, { desc = 'Rename Symbol' })
  keymap('n', '<leader>cf', vim.lsp.buf.format, { desc = 'Format Document' })
  keymap('n', 'gd', vim.lsp.buf.definition, { desc = 'Go to Definition' })
  keymap('n', 'gi', vim.lsp.buf.implementation, { desc = 'Go to Implementation' })

  -- 终端操作
  keymap('n', '<leader>t', '<cmd>terminal<CR>', { desc = 'Open Terminal' })
end
