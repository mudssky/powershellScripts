# 插件使用指南

## 📋 目录

- [核心增强插件](#核心增强插件)
  - [Flash.nvim - 快速跳转](#flashnvim---快速跳转)
  - [nvim-surround - 包围符号操作](#nvim-surround---包围符号操作)
  - [Comment.nvim - 智能注释](#commentnvim---智能注释)
  - [mini.ai - 增强文本对象](#miniai---增强文本对象)
- [UI/UX 插件](#uiux-插件)
  - [主题配置](#主题配置)
  - [状态栏](#状态栏)
  - [缓冲区标签栏](#缓冲区标签栏)
  - [文件树](#文件树)
  - [通知系统](#通知系统)
  - [缩进线显示](#缩进线显示)
  - [图标支持](#图标支持)
- [开发工具插件](#开发工具插件)
  - [LSP 语言服务器](#lsp-语言服务器)
  - [语法高亮](#语法高亮)
  - [模糊查找](#模糊查找)
  - [终端管理](#终端管理)
- [辅助插件](#辅助插件)
  - [键位提示](#键位提示)
- [插件配置技巧](#插件配置技巧)
- [故障排除](#故障排除)

## 🚀 核心增强插件

### Flash.nvim - 快速跳转

**插件地址**: [folke/flash.nvim](https://github.com/folke/flash.nvim)

#### 功能概述

Flash.nvim 是一个现代化的快速跳转插件，提供了比传统 EasyMotion 更强大和直观的跳转体验。

#### 配置文件位置

`lua/plugins/flash.lua`

#### 基础使用

##### 字符跳转

```text
s + 字符    # 跳转到指定字符的位置
S + 字符    # 反向跳转到指定字符的位置
```

**示例**:

```text
原文本: The quick brown fox jumps over the lazy dog
按键: s + o
结果: 显示所有 'o' 字符的跳转标签，选择对应标签即可跳转
```

##### 智能跳转

```text
S          # 基于语法树的智能跳转（Treesitter 跳转）
```

#### 高级功能

##### 多字符搜索

```text
s + 多个字符  # 搜索多字符组合
例如: s + th   # 搜索 "th" 组合
```

##### 可视模式跳转

```text
# 在可视模式下使用
v + s + 字符   # 选择到跳转位置的文本
```

##### 操作符模式跳转

```text
d + s + 字符   # 删除到跳转位置的文本
y + s + 字符   # 复制到跳转位置的文本
c + s + 字符   # 修改到跳转位置的文本
```

#### 配置选项

```lua
require("flash").setup({
  labels = "asdfghjklqwertyuiopzxcvbnm", -- 跳转标签字符
  search = {
    multi_window = true,    -- 跨窗口搜索
    forward = true,         -- 向前搜索
    wrap = true,           -- 循环搜索
  },
  jump = {
    jumplist = true,       -- 添加到跳转列表
    pos = "start",         -- 跳转位置（start/end）
  },
  label = {
    uppercase = false,     -- 使用大写标签
    rainbow = {
      enabled = false,     -- 彩虹标签
    },
  },
})
```

#### 使用技巧

1. **快速导航**: 使用 `s` + 目标字符快速跳转到屏幕上的任意位置
2. **精确选择**: 在多个相同字符时，Flash 会显示标签供选择
3. **组合操作**: 结合 Vim 操作符（d、y、c）实现快速编辑
4. **跨窗口跳转**: 在多窗口环境下可以跳转到其他窗口

---

### nvim-surround - 包围符号操作

**插件地址**: [kylechui/nvim-surround](https://github.com/kylechui/nvim-surround)

#### 功能概述

快速添加、删除、修改包围符号（括号、引号、标签等）。

#### 配置文件位置

`lua/plugins/surround.lua`

#### 基础操作

##### 添加包围符号

```text
ys{motion}{char}   # 给 motion 选中的文本添加包围符号
yss{char}          # 给整行添加包围符号
ysiw{char}         # 给当前单词添加包围符号
```

**示例**:

```text
原文本: hello world
操作: ysiw"         # 给当前单词添加双引号
结果: "hello" world

原文本: hello world
操作: yss)          # 给整行添加括号
结果: (hello world)
```

##### 删除包围符号

```text
ds{char}           # 删除指定的包围符号
```

**示例**:

```text
原文本: "hello world"
操作: ds"           # 删除双引号
结果: hello world

原文本: (hello world)
操作: ds)           # 删除括号
结果: hello world
```

##### 修改包围符号

```text
cs{old}{new}       # 将旧的包围符号替换为新的
```

**示例**:

```text
原文本: "hello world"
操作: cs"'          # 将双引号替换为单引号
结果: 'hello world'

原文本: (hello world)
操作: cs)]          # 将圆括号替换为方括号
结果: [hello world]
```

#### 可视模式操作

```text
# 在可视模式下选择文本后
S{char}            # 给选中的文本添加包围符号
```

**示例**:

```text
1. 使用 v 进入可视模式
2. 选择文本 "hello world"
3. 按 S"
4. 结果: "hello world"
```

#### 支持的包围符号

##### 基础符号

```text
"  '  `          # 引号
(  )  [  ]  {  } # 括号
<  >             # 尖括号
```

##### HTML/XML 标签

```text
t                # HTML 标签
例如: yst<p>     # 添加 <p> 标签
```

##### 自定义符号

可以在配置中添加自定义的包围符号：

```lua
require("nvim-surround").setup({
  surrounds = {
    ["*"] = {
      add = { "*", "*" },
      find = "*.-*",
      delete = "^(.)().-(.)()$",
    },
  },
})
```

#### 高级用法

##### 函数调用包围

```text
ysiw)              # 给单词添加函数调用括号
例如: hello → hello()

ysiwf              # 添加函数调用并进入插入模式输入函数名
例如: hello → function_name(hello)
```

##### 多行操作

```text
yss{char}          # 给整行添加包围符号
ySS{char}          # 给整行添加包围符号（新行格式）
```

**示例**:

```text
原文本: hello world
操作: ySS)         # 添加括号并格式化
结果:
(
    hello world
)
```

#### 使用技巧

1. **快速引号切换**: 使用 `cs"'` 快速在不同引号间切换
2. **HTML 标签操作**: 使用 `cst<div>` 快速修改 HTML 标签
3. **批量操作**: 结合宏录制实现批量包围符号操作
4. **嵌套操作**: 可以对已有包围符号再次添加新的包围符号

---

### Comment.nvim - 智能注释

**插件地址**: [numToStr/Comment.nvim](https://github.com/numToStr/Comment.nvim)

#### 功能概述

智能的代码注释切换插件，支持多种编程语言的行注释和块注释。

#### 配置文件位置

`lua/plugins/comment.lua`

#### 基础操作

##### 行注释

```text
gcc                # 切换当前行注释
gc{motion}         # 注释 motion 选中的内容
gc{count}cc        # 注释指定行数
```

**示例**:

```text
# JavaScript 文件
原文本: console.log("Hello World");
操作: gcc
结果: // console.log("Hello World");

# Python 文件
原文本: print("Hello World")
操作: gcc
结果: # print("Hello World")
```

##### 块注释

```text
gbc                # 切换当前行块注释
gb{motion}         # 块注释 motion 选中的内容
```

**示例**:

```text
# JavaScript 文件
原文本: console.log("Hello World");
操作: gbc
结果: /* console.log("Hello World"); */
```

#### 可视模式操作

```text
# 在可视模式下选择文本后
gc                 # 切换行注释
gb                 # 切换块注释
```

#### 高级功能

##### 智能注释检测

Comment.nvim 会自动检测文件类型并使用相应的注释符号：

```text
.js, .ts    →  // 和 /* */
.py         →  #
.lua        →  -- 和 --[[ ]]
.html       →  <!-- -->
.css        →  /* */
.vim        →  "
```

##### 注释文本对象

```text
gc{motion}         # 使用任意 motion
例如:
gciw               # 注释当前单词
gcip               # 注释当前段落
gc$                # 注释到行尾
gcG                # 注释到文件末尾
```

##### 计数操作

```text
3gcc               # 注释当前行及下面 2 行（共 3 行）
gc2j               # 注释当前行及下面 2 行
```

#### 配置选项

```lua
require('Comment').setup({
  -- 基础配置
  padding = true,           -- 注释符号后添加空格
  sticky = true,            -- 光标保持在原位置
  ignore = '^$',           -- 忽略空行

  -- 切换映射
  toggler = {
    line = 'gcc',           -- 行注释切换
    block = 'gbc'           -- 块注释切换
  },

  -- 操作符映射
  opleader = {
    line = 'gc',            -- 行注释操作符
    block = 'gb'            -- 块注释操作符
  },

  -- 额外映射
  extra = {
    above = 'gcO',          -- 在上方添加注释
    below = 'gco',          # 在下方添加注释
    eol = 'gcA',            # 在行尾添加注释
  },

  -- 预处理钩子
  pre_hook = function(ctx)
    -- 可以在注释前执行自定义逻辑
  end,

  -- 后处理钩子
  post_hook = function(ctx)
    -- 可以在注释后执行自定义逻辑
  end,
})
```

#### 与 VSCode 集成

在 VSCode 环境下，Comment.nvim 与 VSCode 的注释功能协同工作：

```lua
-- 在 VSCode 中使用 VSCode 的注释命令
if vim.g.vscode then
  vim.keymap.set('n', 'gcc', '<cmd>call VSCodeNotify("editor.action.commentLine")<cr>')
  vim.keymap.set('x', 'gc', '<cmd>call VSCodeNotify("editor.action.commentLine")<cr>')
end
```

#### 使用技巧

1. **快速切换**: 使用 `gcc` 快速切换单行注释
2. **批量注释**: 在可视模式下选择多行后使用 `gc`
3. **智能检测**: 插件会自动识别文件类型使用正确的注释符号
4. **嵌套注释**: 支持嵌套注释的语言会正确处理嵌套情况
5. **自定义语言**: 可以为不支持的语言添加自定义注释规则

---

### mini.ai - 增强文本对象

**插件地址**: [echasnovski/mini.ai](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-ai.md)

#### 功能概述

mini.ai 提供了增强的文本对象，扩展了 Vim 原生的文本对象功能，支持更智能的代码块选择。

#### 配置文件位置

`lua/plugins/mini-ai.lua`

#### 基础文本对象

##### 原生文本对象增强

```text
aw/iw              # 单词（word）
as/is              # 句子（sentence）
ap/ip              # 段落（paragraph）
a(/i(, a)/i)       # 括号内容
a[/i[, a]/i]       # 方括号内容
a{/i{, a}/i}       # 大括号内容
a"/i", a'/i'       # 引号内容
a`/i`              # 反引号内容
at/it              # HTML/XML 标签
```

##### 新增文本对象

```text
ao/io              # 代码块（函数、循环、条件语句等）
af/if              # 函数
ac/ic              # 类
aa/ia              # 参数
```

#### 使用示例

##### 函数操作

```javascript
// JavaScript 示例
function calculateSum(a, b) {
  const result = a + b;
  return result;
}

# 光标在函数内任意位置
daf                # 删除整个函数
vif                # 选择函数内容（不包括函数声明）
yaf                # 复制整个函数
cif                # 修改函数内容
```

##### 代码块操作

```python
# Python 示例
if condition:
    print("True")
    do_something()
else:
    print("False")
    do_other_thing()

# 光标在 if 块内
dao                # 删除整个 if-else 块
vio                # 选择当前代码块内容
yao                # 复制整个代码块
```

##### 参数操作

```javascript
// JavaScript 示例
function example(param1, param2, param3) {
  // 函数体
}

# 光标在参数上
daa                # 删除当前参数
via                # 选择当前参数
yaa                # 复制当前参数
cia                # 修改当前参数
```

#### 高级功能

##### 智能边界检测

mini.ai 使用 Treesitter 进行智能的语法分析：

```lua
-- 配置示例
require('mini.ai').setup({
  custom_textobjects = {
    o = require('mini.ai').gen_spec.treesitter({
      a = { '@block.outer', '@conditional.outer', '@loop.outer' },
      i = { '@block.inner', '@conditional.inner', '@loop.inner' },
    }),
    f = require('mini.ai').gen_spec.treesitter({
      a = '@function.outer',
      i = '@function.inner',
    }),
    c = require('mini.ai').gen_spec.treesitter({
      a = '@class.outer',
      i = '@class.inner',
    }),
  },
})
```

##### 自定义文本对象

可以定义自己的文本对象：

```lua
require('mini.ai').setup({
  custom_textobjects = {
    -- 自定义数字文本对象
    d = { '%f[%d]%d+' },

    -- 自定义 URL 文本对象
    u = {
      { 'https?://[%w_.-]+' },
    },

    -- 基于函数的文本对象
    e = function()
      local from = { line = 1, col = 1 }
      local to = {
        line = vim.fn.line('$'),
        col = math.max(vim.fn.getline('$'):len(), 1)
      }
      return { from = from, to = to }
    end,
  },
})
```

#### 语言特定支持

mini.ai 对不同编程语言提供了特定的支持：

##### JavaScript/TypeScript

```javascript
// 类方法
class MyClass {
  method() {
    // 方法体
  }
}

# 在方法内使用 daf 删除整个方法
# 使用 vif 选择方法体
```

##### Python

```python
# 类和方法
class MyClass:
    def method(self, param):
        return param * 2

# 在方法内使用 dac 删除整个类
# 使用 vif 选择方法体
```

##### Lua

```lua
-- 函数定义
local function calculate(a, b)
  return a + b
end

-- 在函数内使用 daf 删除整个函数
-- 使用 vif 选择函数体
```

#### 使用技巧

1. **快速重构**: 使用 `cif` 快速修改函数内容
2. **代码移动**: 使用 `yaf` 复制函数，然后粘贴到其他位置
3. **批量操作**: 结合宏录制对多个函数执行相同操作
4. **嵌套选择**: 在嵌套结构中使用不同的文本对象精确选择
5. **组合使用**: 与其他插件（如 surround）组合使用实现复杂操作

---

## 🎨 UI/UX 插件

### 主题配置

**插件地址**: [folke/tokyonight.nvim](https://github.com/folke/tokyonight.nvim)

#### 配置文件位置

`lua/plugins/theme.lua`

#### 主题变体

```lua
-- 可用的主题变体
tokyonight-night    # 深色主题（默认）
tokyonight-storm    # 暴风雨主题
tokyonight-day      # 浅色主题
tokyonight-moon     # 月光主题
```

#### 配置选项

```lua
require("tokyonight").setup({
  style = "night",           # 主题变体
  light_style = "day",       # 浅色模式时使用的变体
  transparent = false,       # 透明背景
  terminal_colors = true,    # 配置终端颜色
  styles = {
    comments = { italic = true },
    keywords = { italic = true },
    functions = {},
    variables = {},
    sidebars = "dark",       # 侧边栏样式
    floats = "dark",         # 浮动窗口样式
  },
  sidebars = { "qf", "help" }, # 应用深色样式的侧边栏
  day_brightness = 0.3,      # 浅色主题亮度调整
  hide_inactive_statusline = false, # 隐藏非活动状态栏
  dim_inactive = false,      # 使非活动窗口变暗
  lualine_bold = false,      # 状态栏粗体
})
```

### 状态栏

**插件地址**: [nvim-lualine/lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)

#### 配置文件位置

`lua/plugins/statusline.lua`

#### 基础配置

```lua
require('lualine').setup({
  options = {
    icons_enabled = true,
    theme = 'tokyonight',
    component_separators = { left = '', right = ''},
    section_separators = { left = '', right = ''},
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
    }
  },
  sections = {
    lualine_a = {'mode'},
    lualine_b = {'branch', 'diff', 'diagnostics'},
    lualine_c = {'filename'},
    lualine_x = {'encoding', 'fileformat', 'filetype'},
    lualine_y = {'progress'},
    lualine_z = {'location'}
  },
})
```

#### 自定义组件

```lua
-- 自定义 LSP 状态组件
local function lsp_status()
  local clients = vim.lsp.get_active_clients()
  if next(clients) == nil then
    return 'No LSP'
  end

  local client_names = {}
  for _, client in pairs(clients) do
    table.insert(client_names, client.name)
  end

  return ' ' .. table.concat(client_names, ', ')
end

-- 在配置中使用
sections = {
  lualine_x = { lsp_status, 'encoding', 'fileformat', 'filetype' },
}
```

### 缓冲区标签栏

**插件地址**: [akinsho/bufferline.nvim](https://github.com/akinsho/bufferline.nvim)

#### 配置文件位置

`lua/plugins/bufferline.lua`

#### 基础功能

```lua
-- 缓冲区导航键位
vim.keymap.set('n', '<Tab>', '<cmd>BufferLineCycleNext<cr>')
vim.keymap.set('n', '<S-Tab>', '<cmd>BufferLineCyclePrev<cr>')
vim.keymap.set('n', '<leader>bd', '<cmd>bdelete<cr>')
vim.keymap.set('n', '<leader>bo', '<cmd>BufferLineCloseOthers<cr>')
```

#### 高级配置

```lua
require('bufferline').setup({
  options = {
    mode = "buffers",
    numbers = "none",
    close_command = "bdelete! %d",
    right_mouse_command = "bdelete! %d",
    left_mouse_command = "buffer %d",
    middle_mouse_command = nil,
    indicator = {
      icon = '▎',
      style = 'icon',
    },
    buffer_close_icon = '',
    modified_icon = '●',
    close_icon = '',
    left_trunc_marker = '',
    right_trunc_marker = '',
    diagnostics = "nvim_lsp",
    diagnostics_update_in_insert = false,
    offsets = {
      {
        filetype = "NvimTree",
        text = "File Explorer",
        text_align = "left",
        separator = true
      }
    },
    color_icons = true,
    show_buffer_icons = true,
    show_buffer_close_icons = true,
    show_close_icon = true,
    show_tab_indicators = true,
    persist_buffer_sort = true,
    separator_style = "slant",
    enforce_regular_tabs = false,
    always_show_bufferline = true,
    sort_by = 'insert_after_current',
  },
})
```

### 文件树

**插件地址**: [nvim-tree/nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)

#### 配置文件位置

`lua/plugins/nvim-tree.lua`

#### 基础操作

```text
<leader>e          # 切换文件树
o 或 <Enter>       # 打开文件/文件夹
a                  # 创建文件/文件夹
d                  # 删除文件/文件夹
r                  # 重命名文件/文件夹
x                  # 剪切文件/文件夹
c                  # 复制文件/文件夹
p                  # 粘贴文件/文件夹
y                  # 复制文件名
Y                  # 复制相对路径
gy                 # 复制绝对路径
<C-k>              # 显示文件信息
<C-r>              # 刷新文件树
```

#### 高级配置

```lua
require('nvim-tree').setup({
  disable_netrw = true,
  hijack_netrw = true,
  open_on_tab = false,
  hijack_cursor = false,
  update_cwd = true,
  diagnostics = {
    enable = true,
    icons = {
      hint = "",
      info = "",
      warning = "",
      error = "",
    }
  },
  update_focused_file = {
    enable = true,
    update_cwd = true,
    ignore_list = {}
  },
  git = {
    enable = true,
    ignore = true,
    timeout = 500,
  },
  view = {
    width = 30,
    side = 'left',
    preserve_window_proportions = false,
    number = false,
    relativenumber = false,
    signcolumn = "yes",
  },
  renderer = {
    add_trailing = false,
    group_empty = false,
    highlight_git = false,
    full_name = false,
    highlight_opened_files = "none",
    root_folder_modifier = ":~",
    indent_markers = {
      enable = false,
      icons = {
        corner = "└ ",
        edge = "│ ",
        item = "│ ",
        none = "  ",
      },
    },
    icons = {
      webdev_colors = true,
      git_placement = "before",
      padding = " ",
      symlink_arrow = " ➛ ",
      show = {
        file = true,
        folder = true,
        folder_arrow = true,
        git = true,
      },
    },
  },
})
```

### 通知系统

**插件地址**: [rcarriga/nvim-notify](https://github.com/rcarriga/nvim-notify)

#### 配置文件位置

`lua/plugins/notify.lua`

#### 基础使用

```lua
-- 显示通知
vim.notify("Hello World", vim.log.levels.INFO)
vim.notify("Warning message", vim.log.levels.WARN)
vim.notify("Error occurred", vim.log.levels.ERROR)
```

#### 配置选项

```lua
require("notify").setup({
  background_colour = "NotifyBackground",
  fps = 30,
  icons = {
    DEBUG = "",
    ERROR = "",
    INFO = "",
    TRACE = "✎",
    WARN = ""
  },
  level = 2,
  minimum_width = 50,
  render = "default",
  stages = "fade_in_slide_out",
  timeout = 5000,
  top_down = true
})

-- 设置为默认通知函数
vim.notify = require("notify")
```

### 缩进线显示

**插件地址**: [lukas-reineke/indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim)

#### 配置文件位置

`lua/plugins/indent.lua`

#### 基础配置

```lua
require("ibl").setup({
  indent = {
    char = "│",
    tab_char = "│",
  },
  scope = {
    enabled = false,
  },
  exclude = {
    filetypes = {
      "help",
      "alpha",
      "dashboard",
      "neo-tree",
      "Trouble",
      "lazy",
      "mason",
      "notify",
      "toggleterm",
      "lazyterm",
    },
  },
})
```

### 图标支持

**插件地址**: [echasnovski/mini.icons](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-icons.md)

#### 配置文件位置

`lua/plugins/icons.lua`

#### 基础配置

```lua
require('mini.icons').setup({
  -- 文件图标
  file = {
    ['.gitignore'] = { glyph = '', hl = 'MiniIconsGrey' },
    ['README.md'] = { glyph = '', hl = 'MiniIconsYellow' },
  },

  -- 文件类型图标
  filetype = {
    lua = { glyph = '', hl = 'MiniIconsBlue' },
    python = { glyph = '', hl = 'MiniIconsYellow' },
    javascript = { glyph = '', hl = 'MiniIconsYellow' },
  },

  -- 扩展名图标
  extension = {
    lua = { glyph = '', hl = 'MiniIconsBlue' },
    py = { glyph = '', hl = 'MiniIconsYellow' },
    js = { glyph = '', hl = 'MiniIconsYellow' },
  },
})
```

---

## 🛠️ 开发工具插件

### LSP 语言服务器

**插件地址**: [neovim/nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)

#### 配置文件位置

`lua/plugins/lsp.lua`

#### 支持的语言服务器

```lua
-- 常用语言服务器
local servers = {
  lua_ls = {},           -- Lua
  pyright = {},          -- Python
  tsserver = {},         -- TypeScript/JavaScript
  rust_analyzer = {},    -- Rust
  gopls = {},           -- Go
  clangd = {},          -- C/C++
  html = {},            -- HTML
  cssls = {},           -- CSS
  jsonls = {},          -- JSON
}
```

#### 基础键位映射

```lua
-- LSP 相关键位映射
vim.keymap.set('n', 'gd', vim.lsp.buf.definition)
vim.keymap.set('n', 'gD', vim.lsp.buf.declaration)
vim.keymap.set('n', 'gi', vim.lsp.buf.implementation)
vim.keymap.set('n', 'gr', vim.lsp.buf.references)
vim.keymap.set('n', 'K', vim.lsp.buf.hover)
vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help)
vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename)
vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action)
vim.keymap.set('n', '<leader>f', vim.lsp.buf.format)
```

#### 诊断配置

```lua
vim.diagnostic.config({
  virtual_text = {
    enabled = true,
    source = "if_many",
    prefix = "●",
  },
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = {
    focusable = false,
    style = "minimal",
    border = "rounded",
    source = "always",
    header = "",
    prefix = "",
  },
})
```

### 语法高亮

**插件地址**: [nvim-treesitter/nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)

#### 配置文件位置

`lua/plugins/treesitter.lua`

#### 基础配置

```lua
require('nvim-treesitter.configs').setup({
  ensure_installed = {
    "lua", "python", "javascript", "typescript", "html", "css",
    "json", "yaml", "markdown", "bash", "vim", "regex"
  },

  sync_install = false,
  auto_install = true,

  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false,
  },

  indent = {
    enable = true,
  },

  incremental_selection = {
    enable = true,
    keymaps = {
      init_selection = "gnn",
      node_incremental = "grn",
      scope_incremental = "grc",
      node_decremental = "grm",
    },
  },
})
```

#### 高级功能

##### 增量选择

```text
gnn                # 开始增量选择
grn                # 扩展选择到下一个节点
grc                # 扩展选择到作用域
grm                # 缩小选择
```

##### 文本对象

```text
af/if              # 函数
ac/ic              # 类
aa/ia              # 参数
```

### 模糊查找

**插件地址**: [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

#### 配置文件位置

`lua/plugins/telescope.lua`

#### 基础操作

```text
<leader>ff         # 查找文件
<leader>fg         # 全局搜索
<leader>fb         # 查找缓冲区
<leader>fh         # 查找帮助
<leader>fr         # 最近文件
<leader>fc         # 查找命令
<leader>fk         # 查找键位映射
```

#### Telescope 内部键位

```text
<C-n>/<Down>       # 下一个结果
<C-p>/<Up>         # 上一个结果
<C-c>/<Esc>        # 关闭 Telescope
<CR>               # 选择并打开
<C-x>              # 水平分割打开
<C-v>              # 垂直分割打开
<C-t>              # 新标签页打开
<C-u>              # 向上滚动预览
<C-d>              # 向下滚动预览
<C-q>              # 发送到快速修复列表
<M-q>              # 发送所有到快速修复列表
```

#### 高级配置

```lua
require('telescope').setup({
  defaults = {
    prompt_prefix = " ",
    selection_caret = " ",
    path_display = { "truncate" },
    file_ignore_patterns = {
      "node_modules",
      ".git/",
      "dist/",
      "build/",
    },
    mappings = {
      i = {
        ["<C-n>"] = "move_selection_next",
        ["<C-p>"] = "move_selection_previous",
        ["<C-c>"] = "close",
        ["<Down>"] = "move_selection_next",
        ["<Up>"] = "move_selection_previous",
        ["<CR>"] = "select_default",
        ["<C-x>"] = "select_horizontal",
        ["<C-v>"] = "select_vertical",
        ["<C-t>"] = "select_tab",
        ["<C-u>"] = "preview_scrolling_up",
        ["<C-d>"] = "preview_scrolling_down",
      },
    },
  },
  pickers = {
    find_files = {
      theme = "dropdown",
      previewer = false,
    },
    live_grep = {
      theme = "ivy",
    },
  },
  extensions = {
    fzf = {
      fuzzy = true,
      override_generic_sorter = true,
      override_file_sorter = true,
      case_mode = "smart_case",
    },
  },
})
```

### 终端管理

**插件地址**: [akinsho/toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)

#### 配置文件位置

`lua/plugins/toggleterm.lua`

#### 基础操作

```text
<C-\>              # 切换终端
<leader>tf         # 浮动终端
<leader>th         # 水平终端
<leader>tv         # 垂直终端
```

#### 终端内操作

```text
<C-\>              # 切换回编辑器
<C-h/j/k/l>        # 窗口导航
exit               # 退出终端
```

#### 高级配置

```lua
require("toggleterm").setup({
  size = 20,
  open_mapping = [[<c-\>]],
  hide_numbers = true,
  shade_filetypes = {},
  shade_terminals = true,
  shading_factor = 2,
  start_in_insert = true,
  insert_mappings = true,
  terminal_mappings = true,
  persist_size = true,
  direction = 'float',
  close_on_exit = true,
  shell = vim.o.shell,
  float_opts = {
    border = 'curved',
    winblend = 0,
    highlights = {
      border = "Normal",
      background = "Normal",
    },
  },
})
```

---

## 🔧 辅助插件

### 键位提示

**插件地址**: [folke/which-key.nvim](https://github.com/folke/which-key.nvim)

#### 配置文件位置

`lua/plugins/which-key.lua`

#### 基础功能

当你按下 `<leader>` 键后稍等片刻，which-key 会显示所有可用的键位组合。

#### 自定义键位组

```lua
local wk = require("which-key")

wk.register({
  f = {
    name = "file", -- 可选的组名
    f = { "<cmd>Telescope find_files<cr>", "Find File" },
    r = { "<cmd>Telescope oldfiles<cr>", "Open Recent File" },
    n = { "<cmd>enew<cr>", "New File" },
  },
}, { prefix = "<leader>" })
```

#### 高级配置

```lua
require("which-key").setup({
  plugins = {
    marks = true,
    registers = true,
    spelling = {
      enabled = true,
      suggestions = 20,
    },
    presets = {
      operators = false,
      motions = true,
      text_objects = true,
      windows = true,
      nav = true,
      z = true,
      g = true,
    },
  },
  operators = { gc = "Comments" },
  key_labels = {
    ["<space>"] = "SPC",
    ["<cr>"] = "RET",
    ["<tab>"] = "TAB",
  },
  icons = {
    breadcrumb = "»",
    separator = "➜",
    group = "+",
  },
  popup_mappings = {
    scroll_down = "<c-d>",
    scroll_up = "<c-u>",
  },
  window = {
    border = "rounded",
    position = "bottom",
    margin = { 1, 0, 1, 0 },
    padding = { 2, 2, 2, 2 },
    winblend = 0,
  },
  layout = {
    height = { min = 4, max = 25 },
    width = { min = 20, max = 50 },
    spacing = 3,
    align = "left",
  },
  ignore_missing = true,
  hidden = { "<silent>", "<cmd>", "<Cmd>", "<CR>", "call", "lua", "^:", "^ " },
  show_help = true,
  triggers = "auto",
  triggers_blacklist = {
    i = { "j", "k" },
    v = { "j", "k" },
  },
})
```

---

## 🔧 插件配置技巧

### 条件加载

#### 环境检测

```lua
local utils = require('utils')

return {
  "plugin-name",
  cond = not utils.is_vscode(), -- 仅在非 VSCode 环境加载
  -- 其他配置...
}
```

#### 功能检测

```lua
return {
  "plugin-name",
  cond = function()
    return vim.fn.executable("git") == 1 -- 仅在有 git 时加载
  end,
}
```

### 延迟加载策略

#### 事件触发

```lua
return {
  "plugin-name",
  event = "VeryLazy",        -- 在 Neovim 完全启动后加载
  -- event = "BufReadPost",  -- 在读取缓冲区后加载
  -- event = "InsertEnter",  -- 在进入插入模式时加载
}
```

#### 键位触发

```lua
return {
  "plugin-name",
  keys = {
    { "<leader>f", desc = "Find files" },
    { "<C-p>", mode = "i", desc = "Completion" },
  },
}
```

#### 命令触发

```lua
return {
  "plugin-name",
  cmd = { "PluginCommand", "AnotherCommand" },
}
```

#### 文件类型触发

```lua
return {
  "plugin-name",
  ft = { "lua", "python", "javascript" },
}
```

### 依赖管理

```lua
return {
  "main-plugin",
  dependencies = {
    "required-plugin",           -- 必需依赖
    {
      "optional-plugin",         -- 可选依赖
      config = function()
        -- 可选依赖的配置
      end,
    },
  },
}
```

### 配置模式

#### 简单配置

```lua
return {
  "plugin-name",
  config = true, -- 使用默认配置
}
```

#### 自定义配置

```lua
return {
  "plugin-name",
  config = function()
    require("plugin-name").setup({
      -- 自定义配置选项
    })
  end,
}
```

#### 配置选项传递

```lua
return {
  "plugin-name",
  opts = {
    -- 配置选项，会自动传递给 setup() 函数
  },
}
```

### 键位映射最佳实践

#### 描述性映射

```lua
keys = {
  {
    "<leader>ff",
    "<cmd>Telescope find_files<cr>",
    desc = "Find files",
    mode = "n",
  },
  {
    "<leader>fg",
    function()
      require("telescope.builtin").live_grep()
    end,
    desc = "Live grep",
  },
}
```

#### 模式特定映射

```lua
keys = {
  { "<C-n>", mode = { "n", "v" } },  -- 普通和可视模式
  { "<C-p>", mode = "i" },           -- 插入模式
  { "<leader>x", mode = "x" },       -- 可视模式
}
```

---

## 🔧 故障排除

### 常见问题

#### 1. 插件无法加载

**症状**: 启动时出现插件错误或插件功能不可用

**诊断步骤**:

```vim
:Lazy                    # 检查插件状态
:Lazy log                # 查看加载日志
:checkhealth             # 检查 Neovim 健康状态
:checkhealth lazy        # 检查 lazy.nvim 状态
```

**解决方案**:

1. 检查插件配置语法
2. 确认依赖插件已安装
3. 重新安装插件：`:Lazy clean` 然后 `:Lazy install`
4. 检查 Neovim 版本兼容性

#### 2. 键位映射不工作

**症状**: 按键无响应或执行错误命令

**诊断步骤**:

```vim
:map <leader>ff          # 检查特定键位映射
:verbose map <leader>ff  # 查看键位映射来源
:WhichKey                # 查看可用键位（如果安装了 which-key）
```

**解决方案**:

1. 检查键位冲突
2. 确认插件已正确加载
3. 验证键位映射语法
4. 检查模式设置（normal/insert/visual）

#### 3. VSCode 集成问题

**症状**: 在 VSCode 中某些功能不工作

**诊断步骤**:

```lua
-- 检查 VSCode 环境
print(vim.g.vscode)      -- 应该返回 true

-- 测试 VSCode 命令调用
vim.fn.VSCodeNotify('workbench.action.quickOpen')
```

**解决方案**:

1. 确认 VSCode Neovim 插件已启用
2. 检查 VSCode 设置中的 Neovim 路径
3. 重启 VSCode
4. 更新 VSCode Neovim 插件

#### 4. 性能问题

**症状**: 启动缓慢或编辑器响应迟钝

**诊断步骤**:

```vim
:Lazy profile            # 查看插件加载时间
:startuptime             # 查看启动时间分析
```

**解决方案**:

1. 使用延迟加载（`event = "VeryLazy"`）
2. 减少启动时加载的插件
3. 优化插件配置
4. 禁用不必要的功能

#### 5. LSP 问题

**症状**: 语言服务器功能不工作

**诊断步骤**:

```vim
:LspInfo                 # 查看 LSP 状态
:checkhealth lsp         # 检查 LSP 健康状态
:lua print(vim.inspect(vim.lsp.get_active_clients()))
```

**解决方案**:

1. 确认语言服务器已安装
2. 检查文件类型检测
3. 验证 LSP 配置
4. 重启 LSP：`:LspRestart`

### 调试技巧

#### 1. 启用调试日志

```lua
vim.lsp.set_log_level("debug")
-- 日志文件位置: ~/.cache/nvim/lsp.log
```

#### 2. 插件特定调试

```lua
-- 为特定插件启用调试
require("plugin-name").setup({
  debug = true,
  log_level = "debug",
})
```

#### 3. 配置验证

```lua
-- 检查配置是否正确加载
local ok, config = pcall(require, "plugin-name")
if not ok then
  vim.notify("Failed to load plugin: " .. config, vim.log.levels.ERROR)
end
```

#### 4. 性能分析

```vim
" 启动时间分析
nvim --startuptime startup.log

" 插件加载时间
:Lazy profile
```

### 维护建议

#### 1. 定期更新

```vim
:Lazy update             # 更新所有插件
:Lazy clean              # 清理未使用的插件
:checkhealth             # 检查系统健康状态
```

#### 2. 配置备份

```bash
# 备份配置文件
cp -r ~/.config/nvim ~/.config/nvim.backup

# 或使用 Git 版本控制
cd ~/.config/nvim
git init
git add .
git commit -m "Initial configuration"
```

#### 3. 测试环境

```bash
# 使用临时配置测试
NVIM_APPNAME=nvim-test nvim
```

#### 4. 文档维护

- 为自定义配置添加注释
- 记录重要的配置更改
- 维护键位映射文档
- 定期审查和清理不需要的配置

---

通过遵循这些指南和最佳实践，你可以充分利用每个插件的功能，构建一个高效且稳定的 Neovim 编辑环境。记住，配置是一个渐进的过程，根据你的实际使用需求逐步调整和优化。
