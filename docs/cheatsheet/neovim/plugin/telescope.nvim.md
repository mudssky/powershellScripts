## Neovim Telescope 速查表

Telescope 是 Neovim 的一个高度可扩展的模糊查找器，可让您快速查找、筛选、预览和选取文件、缓冲区、Git 提交等。这份速查表旨在帮助您快速掌握 Telescope 的常用命令和快捷键。

### 核心概念

Telescope 的核心是 **picker**，它负责从特定来源（如文件系统、Git 仓库）获取条目。每个 picker 都有一个关联的 **finder** 用于查找条目，以及一个 **sorter** 用于对结果进行排序。 **Actions** 则定义了在选中条目后可以执行的操作（如打开文件、复制内容）。

### 常用命令

以下是一些常用的 Telescope 命令，您可以在 Neovim 的命令模式下直接输入使用：

| 命令 | 描述 |
|---|---|
| `:Telescope find_files` | 查找当前目录下的文件。 |
| `:Telescope live_grep` | 在当前目录下的文件中实时搜索文本。 |
| `:Telescope buffers` | 列出并切换当前打开的缓冲区。 |
| `:Telescope help_tags` | 搜索 Neovim 的帮助文档标签。 |
| `:Telescope oldfiles` | 查找最近打开过的文件。 |
| `:Telescope commands` | 搜索 Neovim 的可用命令。 |
| `:Telescope keymaps` | 搜索当前的键位映射。 |
| `:Telescope git_commits` | 浏览 Git 提交记录。 |
| `:Telescope git_status` | 查看 Git 仓库的状态。 |

### 默认快捷键 (在 Telescope 窗口中)

当 Telescope 窗口打开时，您可以使用以下快捷键进行交互：

**普通模式 (Normal Mode)** (进入普通模式请按 `Esc`)

| 快捷键 | 描述 |
|---|---|
| `j` / `k` | 向下/向上移动光标。 |
| `gg` / `G` | 跳转到列表的开头/结尾。 |
| `<CR>` | 在当前窗口中打开选中的条目。 |
| `<C-v>` | 在垂直分割窗口中打开选中的条目。 |
| `<C-s>` | 在水平分割窗口中打开选中的条目。 |
| `<C-t>` | 在新的标签页中打开选中的条目。 |
| `<C-q>` | 将所有搜索结果发送到快速修复列表 (quickfix list)。 |
| `<Tab>` | 多选模式下标记/取消标记条目。 |

**插入模式 (Insert Mode)**

| 快捷键 | 描述 |
|---|---|
| `<C-j>` / `<C-n>` | 向下移动光标。 |
| `<C-k>` / `<C-p>` | 向上移动光标。 |
| `<C-u>` / `<C-d>` | 在预览窗口中向上/向下滚动。 |
| `<C-/>` | 显示当前可用的插入模式快捷键。 |

### 推荐的键位映射 (在 `init.lua` 或相关配置文件中设置)

为了更高效地使用 Telescope，建议在您的 Neovim 配置文件中设置一些快捷键。以下是一些常见的示例 (以 `leader` 键为例，通常是 `空格键` 或 `\`):

```lua
-- 查找文件
vim.keymap.set('n', '<leader>ff', '<cmd>Telescope find_files<cr>', { desc = 'Find files' })

-- 实时文本搜索
vim.keymap.set('n', '<leader>fg', '<cmd>Telescope live_grep<cr>', { desc = 'Live grep' })

-- 查找缓冲区
vim.keymap.set('n', '<leader>fb', '<cmd>Telescope buffers<cr>', { desc = 'Find buffers' })

-- 查找帮助文档
vim.keymap.set('n', '<leader>fh', '<cmd>Telescope help_tags<cr>', { desc = 'Find help tags' })
```

### 实用技巧

*   **多选操作**：在 Telescope 窗口中，可以使用 `<Tab>` 键标记多个条目，然后使用 `<C-q>` 将它们一次性发送到快速修复列表，方便进行批量操作。
*   **预览窗口控制**：在插入模式下，使用 `<C-u>` 和 `<C-d>` 可以在不离开输入框的情况下滚动预览窗口。
*   **忽略文件**：Telescope 默认会使用 `.gitignore` 文件来排除不需要搜索的文件。
*   **自定义**：Telescope 提供了丰富的配置选项，您可以自定义主题、布局、排序逻辑等。

### 扩展插件

Telescope 的强大之处在于其可扩展性。社区开发了许多有用的扩展，让 Telescope 能够与其他插件和工具集成：

*   **telescope-fzf-native.nvim**: 使用 C 编写的原生 FZF 排序器，可以大幅提升性能。
*   **telescope-file-browser.nvim**: 在 Telescope 中实现一个文件浏览器。
*   **telescope-ui-select.nvim**: 将 Neovim 的 `vim.ui.select` 替换为 Telescope 界面，提供更统一的体验。

要安装这些扩展，您需要使用您的插件管理器（如 `lazy.nvim` 或 `packer.nvim`）添加相应的插件，并按照其文档进行配置。
