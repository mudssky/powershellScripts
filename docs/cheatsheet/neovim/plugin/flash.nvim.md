## Flash.nvim 速查表：光速导航你的代码

Flash.nvim 是一款 Neovim 插件，它能让你在代码中进行闪电般快速的导航。通过搜索标签、增强的字符移动和 Treesitter 集成，你可以瞬间跳转到屏幕上的任何位置。

### 核心功能

Flash.nvim 提供了多种强大的功能来提升你的导航效率。

* **搜索集成:** 与常规的 `/` 和 `?` 搜索无缝集成，在匹配项旁边显示标签，以便快速跳转。
* **增强的字符移动:** 强化了 `f`、`t`、`F` 和 `T` 等移动命令的功能。
* **Treesitter 集成:** 高亮并标记光标下 Treesitter 节点的父节点，方便快速选择。
* **跳转模式:** 类似于搜索的独立跳转模式。
* **多种搜索模式:** 支持精确、正则和模糊搜索。
* **多窗口跳转:** 可以在多个窗口之间进行跳转。

### 默认快捷键

以下是 Flash.nvim 的一些默认和推荐的快捷键设置。

| 快捷键 | 模式 | 功能 |
| --- | --- | --- |
| `s` | Normal, Visual, Operator-pending | 触发 `flash.jump()`，进行跳转。 |
| `S` | Normal, Visual, Operator-pending | 触发 `flash.treesitter()`，使用 Treesitter 进行跳转。 |
| `r` | Operator-pending | 触发 `flash.remote()`，在远程位置执行动作。 |
| `R` | Operator-pending, Visual | 触发 `flash.treesitter_search()`，进行 Treesitter 搜索。 |
| `<c-s>` | Command | 触发 `flash.toggle()`，切换 Flash 搜索。 |

### 使用方法

**1. 基本跳转 (`s`)**

在普通模式下，按下 `s`，然后输入你想要跳转到的字符。Flash.nvim 会高亮所有匹配的字符，并为每个匹配项分配一个标签。输入相应的标签即可跳转。

**2. Treesitter 跳转 (`S`)**

按下 `S` 可以激活 Treesitter 模式。这会高亮出当前光标所在位置的所有 Treesitter 节点，并为它们分配标签。输入标签即可选中对应的整个代码块，非常适合用来复制、粘贴或修改函数和代码块。

**3. 与原生搜索集成**

Flash.nvim 可以与 Neovim 的原生搜索功能集成。当你使用 `/` 或 `?` 进行搜索时，Flash.nvim 会自动在搜索结果旁边显示跳转标签。你只需输入标签即可跳转到该匹配项。

**4. 增强的字符移动**

Flash.nvim 增强了 `f` 和 `t` 等字符移动命令。当你使用这些命令时，如果一行中有多个匹配项，它会显示标签让你选择跳转。

### 配置

你可以通过在你的 Neovim 配置文件中添加相应的设置来定制 Flash.nvim 的行为。大多数用户直接使用默认配置即可。

一个常见的配置是使用 `lazy.nvim` 插件管理器进行安装和设置：

```lua

{
  "folke/flash.nvim",
  event = "VeryLazy",
  ---@type Flash.Config
  opts = {},
  -- stylua: ignore
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
    { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
    { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
    { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
    { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
  },
}

```
