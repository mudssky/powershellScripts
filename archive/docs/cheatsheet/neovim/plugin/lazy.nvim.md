# Lazy.nvim Cheatsheet

Lazy.nvim 是一个现代化的 Neovim 插件管理器，提供快速的启动时间、自动延迟加载和强大的插件管理 UI。

## 安装与基本设置

### 引导安装

```lua
-- 引导 lazy.nvim
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

-- 设置 leader 键（应在加载 lazy.nvim 之前设置）
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- 设置 lazy.nvim
require("lazy").setup({
  spec = {
    -- 在此添加你的插件
  },
  -- 安装插件时使用的颜色方案
  install = { colorscheme = { "habamax" } },
  -- 自动检查插件更新
  checker = { enabled = true },
})
```

### 单文件设置

```lua
-- 简单设置，指向包含插件规范的目录
require("lazy").setup("plugins")
```

## 插件规范

### 基本插件规范

```lua
return {
  "folke/tokyonight.nvim",
  lazy = false, -- 确保在启动时加载（如果是主颜色方案）
  priority = 1000, -- 确保在其他启动插件之前加载
  config = function()
    -- 在此处加载颜色方案
    vim.cmd([[colorscheme tokyonight]])
  end,
}
```

### 带选项的插件规范

```lua
return { "me/my-plugin", opts = {} }
```

### 延迟加载插件

```lua
return {
  "nvim-neorg/neorg",
  -- 在文件类型上延迟加载
  ft = "norg",
  -- neorg 的选项。这将自动调用 `require("neorg").setup(opts)`
  opts = {
    load = {
      ["core.defaults"] = {},
    },
  },
}
```

### 事件触发加载

```lua
return {
  "hrsh7th/nvim-cmp",
  -- 在 InsertEnter 时加载 cmp
  event = "InsertEnter",
  -- 这些依赖项只会在 cmp 加载时加载
  -- 依赖项总是延迟加载，除非另有说明
  dependencies = {
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-buffer",
  },
  config = function()
    -- ...
  end,
}
```

### 命令触发加载

```lua
return {
  "dstein64/vim-startuptime",
  -- 在命令上延迟加载
  cmd = "StartupTime",
  -- init 在启动期间执行。Vim 插件的配置通常应在 init 函数中设置
  init = function()
    vim.g.startuptime_tries = 10
  end,
}
```

### 键映射触发加载

```lua
return {
  "Wansmer/treesj",
  keys = {
    { "J", "<cmd>TSJToggle<cr>", desc = "Join Toggle" },
  },
  opts = { use_default_keymaps = false, max_join_length = 150 },
}
```

### 本地插件

```lua
-- 使用 dir 显式配置本地插件
{ dir = "~/projects/secret.nvim" }

-- 使用自定义 URL 获取插件
{ url = "git@github.com:folke/noice.nvim.git" }

-- 使用 dev 选项配置本地插件
-- 这将使用 {config.dev.path}/noice.nvim/ 而不是从 GitHub 获取
-- 使用 dev 选项，你可以轻松地在插件的本地版本和安装版本之间切换
{ "folke/noice.nvim", dev = true }
```

## 延迟加载触发器

```lua
-- 事件触发
-- event = "InsertEnter"

-- 命令触发
-- cmd = "StartupTime"

-- 文件类型触发
-- ft = "norg"

-- 键映射触发
-- keys = { "<C-a>", { "<C-x>", mode = "n" } }
```

## 插件版本控制

```lua
-- Semver 版本控制示例：
-- '*': 最新稳定版本（不包括预发布版）
-- '1.2.x': 以 1.2 开头的任何版本
-- '^1.2.3': 兼容版本（例如 1.3.0、1.4.5，但不包括 2.0.0）
-- '~1.2.3': 兼容版本（例如 1.2.4、1.2.5，但不包括 1.3.0）
-- '>1.2.3': 大于 1.2.3 的版本
-- '>=1.2.3': 大于或等于 1.2.3 的版本
-- '<1.2.3': 小于 1.2.3 的版本
-- '<=1.2.3': 小于或等于 1.2.3 的版本
```

## 命令

### 基本命令

```vim
:Lazy sync [plugins]      " 运行安装、清理和更新
:Lazy update [plugins]    " 更新插件。这也会更新锁文件
:Lazy install [plugins]  " 安装缺失的插件
:Lazy clean [plugins]    " 清理不再需要的插件
:Lazy check [plugins]    " 检查更新并显示日志（git fetch）
:Lazy log [plugins]      " 显示最近的更新
:Lazy restore [plugins]  " 将所有插件更新到锁文件中的状态
:Lazy load {plugins}     " 加载尚未加载的插件。类似于 :packadd
:Lazy reload {plugins}   " 重新加载插件（实验性！！）
:Lazy build {plugins}    " 重新构建插件
:Lazy profile            " 显示详细的性能分析
:Lazy debug              " 显示调试信息
:Lazy health             " 运行 :checkhealth lazy
:Lazy help               " 切换此帮助页面
:Lazy home               " 返回插件列表
:Lazy clear              " 清除已完成的任务
```

### 命令选项

```lua
opts table:
- wait: 为 true 时，调用将等待操作完成
- show: 为 false 时，不会显示 UI
- plugins: 要运行操作的插件名称列表
- concurrency: 限制并发运行的任务数量
```

## 配置选项

### 默认配置

```lua
{
  root = vim.fn.stdpath("data") .. "/lazy", -- 插件安装目录
  defaults = {
    lazy = false, -- 插件是否应该延迟加载？
    version = nil, -- 始终使用最新的 git 提交
    cond = nil, ---@type boolean|fun(self:LazyPlugin):boolean|nil
  },
  spec = nil, ---@type LazySpec
  local_spec = true, -- 加载项目特定的 .lazy.lua 规范文件
  lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json", -- 运行更新后生成的锁文件
  concurrency = jit.os:find("Windows") and (vim.uv.available_parallelism() * 2) or nil,
  git = {
    log = { "-8" }, -- 显示最后 8 次提交
    timeout = 120, -- 终止耗时超过 2 分钟的进程
    url_format = "https://github.com/%s.git",
  },
}
```

### 安装配置

```lua
install = {
  -- 在启动时安装缺失的插件。这不会增加启动时间
  missing = true,
  -- 在启动期间的安装过程中尝试加载这些颜色方案之一
  colorscheme = { "habamax" },
}
```

### 检查器配置

```lua
checker = {
  -- 自动检查插件更新
  enabled = false,
  concurrency = nil, ---@type number? 设置为 1 以非常缓慢地检查更新
  notify = true, -- 找到新更新时获取通知
  frequency = 3600, -- 每小时检查一次更新
  check_pinned = false, -- 检查无法更新的固定包
},
```

### UI 配置

```lua
ui = {
  -- 小于 1 的数字是百分比，大于 1 的数字是固定大小
  size = { width = 0.8, height = 0.8 },
  wrap = true, -- 在 UI 中换行
  -- UI 窗口使用的边框。接受与 |nvim_open_win()| 相同的边框值
  border = "none",
  -- 背景不透明度。0 是完全不透明，100 是完全透明
  backdrop = 60,
  title = nil, ---@type string 仅在边框不是 "none" 时有效
  title_pos = "center", ---@type "center" | "left" | "right"
  -- 在 Lazy 窗口顶部显示药丸
  pills = true, ---@type boolean
  icons = {
    cmd = " ",
    config = "",
    debug = "● ",
    event = " ",
    favorite = " ",
    ft = " ",
    init = " ",
    import = " ",
    keys = " ",
    lazy = "󰒲 ",
    loaded = "●",
    not_loaded = "○",
    plugin = " ",
    runtime = " ",
    require = "󰢱 ",
    source = " ",
    start = " ",
    task = "✔ ",
    list = {
      "●",
      "➜",
      "★",
      "‒",
    },
  },
}
```

## API

### 基本函数

```lua
require("lazy").setup(opts)      -- 设置 lazy.nvim
require("lazy").sync(opts?)      -- 运行安装、清理和更新
require("lazy").update(opts?)    -- 更新插件
require("lazy").install(opts?)   -- 安装缺失的插件
require("lazy").clean(opts?)     -- 清理不再需要的插件
require("lazy").check(opts?)     -- 检查更新
require("lazy").log(opts?)       -- 显示最近的更新
require("lazy").restore(opts?)   -- 恢复插件到锁文件中的状态
require("lazy").load(opts)       -- 加载插件
require("lazy").reload(opts)     -- 重新加载插件
require("lazy").build(opts)      -- 构建插件
require("lazy").profile()        -- 显示性能分析
require("lazy").debug()          -- 显示调试信息
require("lazy").health()         -- 运行健康检查
require("lazy").help()           -- 切换帮助页面
require("lazy").home()           -- 返回插件列表
require("lazy").clear()          -- 清除已完成的任务
```

### 状态 API

```lua
require("lazy").stats()
-- 返回:
{
  -- 到 UIEnter 的启动时间（毫秒）
  startuptime = 0,
  -- 为 true 时，startuptime 是 Neovim 进程的准确 cputime（Linux & macOS）
  -- 这比 `nvim --startuptime` 更准确，因此会稍高一些
  -- 为 false 时，startuptime 是基于与 lazy 开始时的时间戳的增量计算的
  real_cputime = false,
  count = 0, -- 插件总数
  loaded = 0, -- 已加载的插件数量
  times = {}, -- 插件加载时间
}
```

### 状态行组件

```lua
-- 在 lualine.nvim 中显示待更新数量
require("lualine").setup({
  sections = {
    lualine_x = {
      {
        require("lazy.status").updates,
        cond = require("lazy.status").has_updates,
        color = { fg = "#ff9e64" },
      },
    },
  },
})
```

## 用户事件

```lua
-- Lazy.nvim 触发的用户事件
- LazyDone: 当 lazy 完成启动并加载你的配置后
- LazySync: 运行 sync 后
- LazyInstall: 安装后
- LazyUpdate: 更新后
- LazyClean: 清理后
- LazyCheck: 检查更新后
- LazyLog: 运行 log 后
- LazyLoad: 加载插件后。data 属性将包含插件名称
- LazySyncPre: 运行 sync 前
- LazyInstallPre: 安装前
- LazyUpdatePre: 更新前
- LazyCleanPre: 清理前
- LazyCheckPre: 检查更新前
- LazyLogPre: 运行 log 前
- LazyReload: 在更改检测后重新加载插件规范时触发
- VeryLazy: 在 LazyDone 之后和处理 VimEnter 自动命令后触发
- LazyVimStarted: 在 UIEnter 时触发，当 require("lazy").stats().startuptime 已计算时。用于在仪表板上更新启动时间
```

## 锁文件

- 锁文件 (`lazy-lock.json`):
  - 每次更新后更新为已安装的修订版本
  - 建议将其置于版本控制之下
  - 使用 `:Lazy restore` 在其他机器上将插件更新到锁文件中的版本

## 从 Packer.nvim 迁移

```lua
-- packer.nvim -> lazy.nvim
-- setup -> init
-- requires -> dependencies
-- as -> name
-- opt -> lazy
-- run -> build
-- lock -> pin
-- disable=true -> enabled = false
-- tag='*' -> version="*"
-- after 在大多数情况下不需要。使用 `dependencies` 否则
-- wants 在大多数情况下不需要。使用 `dependencies` 否则
-- config 不支持字符串类型，使用 `fun(LazyPlugin)` 代替
-- module 是自动加载的。无需指定
-- keys 规范不同
-- rtp 可以通过以下方式实现：
config = function(plugin)
    vim.opt.rtp:append(plugin.dir .. "/custom-rtp")
end
```

## 结构化插件规范

### 主文件

```lua
-- ~/.config/nvim/lua/plugins.lua
return {
  "folke/neodev.nvim",
  "folke/which-key.nvim",
  { "folke/neoconf.nvim", cmd = "Neoconf" },
}
```

### 导入模块

```lua
require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "lazyvim.plugins.extras.coding.copilot" },
  }
})
```

## 开发和本地插件

```lua
dev = {
  -- 存储本地插件项目的目录。如果使用函数，
  -- 应返回插件目录（例如 `~/projects/plugin-name`）
  ---@type string | fun(plugin: LazyPlugin): string
  path = "~/projects",
  ---@type string[] 匹配这些模式的插件将使用你的本地版本，而不是从 GitHub 获取
  patterns = {}, -- 例如 {"folke"}
  fallback = false, -- 当本地插件不存在时回退到 git
}
```

## 性能优化

```lua
performance = {
  cache = {
    enabled = true,
  },
  reset_packpath = true, -- 重置包路径以提高启动时间
  rtp = {
    reset = true, -- 将运行时路径重置为 $VIMRUNTIME 和你的配置目录
    ---@type string[] 在此处添加要包含在 rtp 中的任何自定义路径
    paths = {}, 
    ---@type string[] 在此处列出要禁用的任何插件
    disabled_plugins = {
      -- "gzip",
      -- "matchit",
      -- "matchparen",
      -- "netrwPlugin",
      -- "tarPlugin",
      -- "tohtml",
      -- "tutor",
      -- "zipPlugin",
    },
  },
},
```

## 卸载路径

```lua
-- 要完全卸载 lazy.nvim，需要删除的默认文件路径和目录
-- 注意：路径可能因 XDG 环境变量而异
- data: ~/.local/share/nvim/lazy
- state: ~/.local/state/nvim/lazy
- lockfile: ~/.config/nvim/lazy-lock.json
```

## 高亮组

```lua
-- Lazy.nvim UI 元素的高亮组
LazyButton              CursorLine              
LazyButtonActive        Visual                  
LazyComment             Comment                 
LazyCommit              @variable.builtin       commit ref
LazyCommitIssue         Number                  
LazyCommitScope         Italic                  conventional commit scope
LazyCommitType          Title                   conventional commit type
LazyDimmed              Conceal                 property
LazyDir                 @markup.link            directory
LazyError               DiagnosticError         task errors
LazyH1                  IncSearch               home button
LazyH2                  Bold                    titles
LazyInfo                DiagnosticInfo          task errors
LazyNoCond              DiagnosticWarn          unloaded icon for a plugin where cond() was false
LazyNormal              NormalFloat             
LazyProgressDone        Constant                progress bar done
```
