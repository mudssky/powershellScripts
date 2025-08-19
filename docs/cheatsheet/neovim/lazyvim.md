## LazyVim 配置说明

LazyVim 是一个基于 lazy.nvim 插件管理器的 Neovim 配置框架，它提供了一套现代化、模块化的配置方案，使 Neovim 的配置变得更加简单和可维护。

### 核心概念

LazyVim 的设计理念是模块化和可扩展性。它将配置分为多个独立的模块，每个模块负责特定的功能，用户可以根据需要选择启用或禁用这些模块。

### Markdown 支持

LazyVim 提供了强大的 Markdown 编辑支持，包括语法高亮、预览、表格格式化等功能。

#### Markdown 大纲视图

在 LazyVim 中，可以使用多种方式查看 Markdown 文件的大纲结构：

##### 使用 neo-tree 大纲视图

Neo-tree 是 LazyVim 中默认的文件树插件，它也支持显示文档的大纲结构。

**快捷键**：
- `<leader>e` - 打开/关闭 neo-tree 文件树
- 在 neo-tree 窗口中按 `o` - 切换到大纲视图
- `Enter` - 跳转到选中的标题位置
- `Tab` - 展开/折叠标题节点

**特点**：
- 可视化显示 Markdown 标题层级结构
- 支持快速跳转到指定标题位置
- 实时同步当前编辑位置

##### 使用 telescope 大纲视图

Telescope 是 LazyVim 中集成的另一个重要插件，提供了强大的模糊查找功能，也包括文档大纲查找。

**命令**：
- `:Telescope marks` - 查看文档中的标记点
- `:MarkdownPreview` - 预览 Markdown 文件（需要安装 markdown-preview.nvim 插件）

**自定义配置**：
可以在 `~/.config/lazyvim/lua/plugins/telescope.lua` 中添加以下配置来增强 Markdown 支持：

```lua
return {
  "nvim-telescope/telescope.nvim",
  opts = {
    pickers = {
      find_files = {
        -- 针对 Markdown 文件的特殊处理
        hidden = true,
      },
    },
  },
}
```

### 常用快捷键

以下是一些 LazyVim 中 Markdown 编辑的常用快捷键：

| 快捷键 | 模式 | 功能 |
|---|---|---|
| `<leader>fm` | Normal | 格式化 Markdown 表格 |
| `<leader>pv` | Normal | 预览 Markdown 文件 |
| `<C-Space>` | Insert | 触发补全 |
| `]]` | Normal | 跳转到下一个标题 |
| `[[` | Normal | 跳转到上一个标题 |

### 插件管理

LazyVim 使用 lazy.nvim 作为插件管理器，配置文件位于 `~/.config/lazyvim/lua/plugins/` 目录下。

#### 添加新插件

在 `~/.config/lazyvim/lua/plugins/` 目录下创建新的 Lua 文件来添加插件：

```lua
-- ~/.config/lazyvim/lua/plugins/example.lua
return {
  "author/plugin-name",
  opts = {
    -- 插件配置选项
  },
}
```

#### 修改现有插件配置

可以直接修改对应插件的配置文件来调整其行为。

### 自定义配置

LazyVim 的自定义配置文件位于 `~/.config/lazyvim/lua/user/` 目录下：

- `init.lua` - 初始化配置
- `keymaps.lua` - 快捷键配置
- `options.lua` - Neovim 选项配置

示例自定义配置：

```lua
-- ~/.config/lazyvim/lua/user/options.lua
local opt = vim.opt

opt.relativenumber = true -- 显示相对行号
opt.wrap = false          -- 不自动换行
```

### 故障排除

#### 插件加载问题

如果遇到插件未正确加载的问题，可以尝试以下步骤：

1. 运行 `:Lazy` 命令检查插件状态
2. 使用 `:Lazy sync` 同步插件
3. 检查插件配置文件是否有语法错误

#### 性能问题

如果发现 Neovim 运行缓慢，可以：

1. 使用 `:Lazy profile` 分析插件加载性能
2. 禁用不必要的插件模块
3. 检查 LSP 服务器配置

### 进一步学习

- 查阅 [LazyVim 官方文档](https://www.lazyvim.org/)
- 参考 [Neovim 官方文档](https://neovim.io/doc/)
- 浏览社区配置示例