-- -----------------------------------------------------------------------------
-- 文件: init.lua
-- 描述: Neovim 主配置文件 - 模块化配置入口
-- 作者: mudssky
-- 更新: 2024
-- -----------------------------------------------------------------------------

-- 设置 leader 键
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- 设置 Nerd Font 支持
vim.g.have_nerd_font = true

-- 加载核心配置
require("core.options")      -- 基础选项配置
require("core.keymaps")      -- 键位映射配置
require("core.lazy").setup() -- lazy.nvim 插件管理器配置

-- 插件配置通过 lazy.nvim 自动加载 plugins/ 目录下的所有文件
-- utils/ 目录下的工具函数可以在需要时通过 require('utils') 加载

-- vim: ts=2 sts=2 sw=2 et
