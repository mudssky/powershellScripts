# VSCode Neovim 配置指南

## 📋 目录

- [简介](#简介)
- [项目结构](#项目结构)
- [安装指南](#安装指南)
- [插件介绍](#插件介绍)
- [键位映射](#键位映射)
- [使用说明](#使用说明)
- [故障排除](#故障排除)
- [详细文档](#详细文档)

## 🎯 简介

这是一个专门为 VSCode Neovim 插件设计的模块化配置文件，旨在：

- ✅ 增强 VSCode 中的 Vim 编辑体验
- ✅ 提供强大的文本操作功能
- ✅ 与 VSCode 功能完美集成
- ✅ 避免与 VSCode 原生功能冲突
- ✅ 保持轻量级和高性能
- ✅ 模块化设计，易于维护和扩展

## 📁 项目结构

```text
neovim/
├── init.lua                 # 主配置文件入口
├── lua/
│   ├── core/               # 核心配置模块
│   │   ├── options.lua     # Neovim 基础选项配置
│   │   ├── keymaps.lua     # 键位映射配置
│   │   └── lazy.lua        # lazy.nvim 插件管理器配置
│   ├── plugins/            # 插件配置模块（模块化拆分）
│   │   ├── bufferline.lua  # 缓冲区标签栏
│   │   ├── comment.lua     # 智能注释
│   │   ├── flash.lua       # 快速跳转
│   │   ├── icons.lua       # 图标支持
│   │   ├── indent.lua      # 缩进线显示
│   │   ├── lsp.lua         # LSP 语言服务器
│   │   ├── mini-ai.lua     # 增强文本对象
│   │   ├── notify.lua      # 通知系统
│   │   ├── nvim-tree.lua   # 文件树
│   │   ├── statusline.lua  # 状态栏
│   │   ├── surround.lua    # 包围符号操作
│   │   ├── telescope.lua   # 模糊查找
│   │   ├── theme.lua       # 主题配置
│   │   ├── toggleterm.lua  # 终端管理
│   │   ├── treesitter.lua  # 语法高亮
│   │   ├── ui.lua          # UI 相关（已拆分为独立模块）
│   │   └── which-key.lua   # 键位提示
│   └── utils/              # 工具函数模块
│       └── init.lua        # 通用工具函数
├── docs/                   # 详细文档目录
└── setup-neovim-vscode.ps1 # 自动化安装脚本
```

## 🚀 安装指南

### 前置要求

1. **安装 VSCode Neovim 插件**

   ```text
   在 VSCode 扩展市场搜索并安装 "VSCode Neovim"
   ```

2. **安装 Neovim**

   ```powershell
   # 使用 Chocolatey
   choco install neovim

   # 或使用 Scoop
   scoop install neovim

   # 或使用 Winget
   winget install Neovim.Neovim
   ```

### 配置安装

1. **调整vscode neovim 插件 vscode配置**
vim 默认的一些ctrl快捷键，不如vscode原生的好用，更习惯。
比如ctrl+c,ctrl+v ,这些快捷键让vscode来处理

```jsonc
{
  // 将这些 Ctrl 快捷键组合发送给 Neovim 在 Normal 模式下处理
  "vscode-neovim.ctrlKeysForNormalMode": [
    "v" // Ctrl+v: 可视化块模式
  ],
  // 将这些 Ctrl 快捷键组合发送给 Neovim 在 Insert 模式下处理
  "vscode-neovim.ctrlKeysForInsertMode": []
}

```

2. **使用提供的 PowerShell 脚本**

   ```powershell
   # 在当前目录运行脚本
   .\setup-neovim-config.ps1

   # 或指定源文件路径
   .\setup-neovim-config.ps1 -SourceConfig "path\to\vscode_init.lua"

   # 强制覆盖现有配置
   .\setup-neovim-config.ps1 -Force
   ```

3. **手动安装**

   ```powershell
   # 创建配置目录
   $configDir = "$env:LOCALAPPDATA\nvim"
   New-Item -ItemType Directory -Path $configDir -Force

   # 创建软链接
   New-Item -ItemType SymbolicLink -Path "$configDir\init.lua" -Target "vscode_init.lua"
   ```

## 🔌 插件介绍

### 核心插件

#### 1. Flash.nvim - 快速跳转

**功能**: 现代化的快速跳转插件，替代传统的 EasyMotion

**使用方法**:

- `s` + 字符: 跳转到指定字符
- `S`: 基于语法树的智能跳转

**配置特点**:

- 启用字符跳转标签
- 支持多种跳转模式
- 与 VSCode 完美集成

#### 2. ReplaceWithRegister - 寄存器替换

**功能**: 使用寄存器内容替换文本，无需进入插入模式

**使用方法**:

- `gr{motion}`: 用寄存器内容替换 motion 选中的文本
- `grr`: 替换整行
- `gr` (可视模式): 替换选中的文本

**使用场景**:

```text
1. 复制一段文本 (yy)
2. 选择要替换的文本
3. 按 gr 即可替换
```

#### 3. nvim-surround - 包围符号操作

**功能**: 快速添加、删除、修改包围符号（括号、引号等）

**使用方法**:

- `ys{motion}{char}`: 添加包围符号
- `ds{char}`: 删除包围符号
- `cs{old}{new}`: 修改包围符号

**示例**:

```text
原文本: hello world
按键: ysiw"     -> "hello" world
按键: ds"        -> hello world
按键: cs"'       -> 'hello' world
```

#### 4. Comment.nvim - 智能注释

**功能**: 智能的代码注释切换，支持多种编程语言

**使用方法**:

- `gcc`: 切换当前行注释
- `gc{motion}`: 注释 motion 选中的内容
- `gc` (可视模式): 注释选中的内容

**特点**:

- 自动识别文件类型
- 支持块注释和行注释
- 智能处理缩进

#### 5. mini.ai - 增强文本对象

**功能**: 提供更强大和智能的文本对象

**新增文本对象**:

- `ao`/`io`: 代码块（函数、循环、条件语句）
- `af`/`if`: 函数
- `ac`/`ic`: 类

**使用示例**:

```text
daf  -> 删除整个函数
vif  -> 选中函数内容
cio  -> 修改代码块内容
```

#### 6. which-key.nvim - 键位提示

**功能**: 显示可用的键位组合（可选，VSCode 已有类似功能）

**特点**:

- 实时显示键位提示
- 支持自定义分组
- 与 VSCode WhichKey 互补

## ⌨️ 键位映射

### 基础键位

| 键位 | 模式 | 功能 | 描述 |
|------|------|------|------|
| `jj` | Insert | `<Esc>` | 快速退出插入模式 |
| `<leader>n` | Normal | `:nohlsearch` | 清除搜索高亮 |
| `j`/`k` | Normal | `gj`/`gk` | 智能行移动 |
| `<C-h/j/k/l>` | Normal | 窗口导航 | 在分割窗口间移动 |
| `>`/`<` | Visual | 缩进调整 | 保持选择状态 |
| `J`/`K` | Visual | 行移动 | 上下移动选中行 |

### VSCode 集成键位

#### 文件操作

| 键位 | 功能 | VSCode 命令 |
|------|------|-------------|
| `<leader>w` | 保存文件 | `workbench.action.files.save` |
| `<leader>ff` | 查找文件 | `workbench.action.quickOpen` |
| `<leader>fg` | 全局搜索 | `workbench.action.findInFiles` |
| `<leader>fs` | 查找符号 | `workbench.action.gotoSymbol` |

#### 界面操作

| 键位 | 功能 | VSCode 命令 |
|------|------|-------------|
| `<leader>e` | 切换资源管理器 | `workbench.view.explorer` |
| `<leader>g` | 切换 Git 面板 | `workbench.view.scm` |
| `<leader>x` | 切换扩展面板 | `workbench.view.extensions` |
| `<leader>t` | 切换终端 | `workbench.action.terminal.toggleTerminal` |
| `<leader>p` | 切换面板 | `workbench.action.togglePanel` |

#### 代码操作

| 键位 | 功能 | VSCode 命令 |
|------|------|-------------|
| `<leader>ca` | 代码操作 | `editor.action.quickFix` |
| `<leader>cr` | 重命名符号 | `editor.action.rename` |
| `<leader>cf` | 格式化文档 | `editor.action.formatDocument` |
| `gd` | 跳转到定义 | `editor.action.revealDefinition` |
| `gr` | 查看引用 | `editor.action.goToReferences` |
| `gi` | 跳转到实现 | `editor.action.goToImplementation` |

#### 书签操作

| 键位 | 功能 | VSCode 命令 |
|------|------|-------------|
| `<leader>bt` | 切换书签 | `bookmarks.toggle` |
| `<leader>bl` | 列出书签 | `bookmarks.listFromAllFiles` |

#### 通用操作

| 键位 | 功能 | 描述 |
|------|------|------|
| `<space>` | WhichKey | 显示可用命令 |
| `<leader>/` | 切换注释 | 注释/取消注释 |

## 📖 使用说明

### 日常工作流程

1. **文件导航**

   ```text
   <leader>ff  -> 快速打开文件
   <leader>fg  -> 全局搜索内容
   <leader>fs  -> 搜索符号
   ```

2. **代码编辑**

   ```text
   s + 字符     -> 快速跳转
   ys + 动作 + 符号 -> 添加包围符号
   gcc         -> 切换注释
   gr + 动作    -> 替换文本
   ```

3. **代码导航**

   ```text
   gd          -> 跳转到定义
   gr          -> 查看引用
   gi          -> 跳转到实现
   ```

4. **界面管理**

   ```text
   <leader>e   -> 切换文件树
   <leader>t   -> 切换终端
   <leader>g   -> 切换 Git 面板
   ```

### 高级技巧

#### 1. 文本对象组合

```text
daf    -> 删除整个函数
vif    -> 选择函数内容
cio    -> 修改代码块内容
yao    -> 复制整个代码块
```

#### 2. 包围符号操作

```text
# 给单词添加引号
ysiw"   -> "word"

# 给整行添加括号
yss)    -> (entire line)

# 修改包围符号
cs"'    -> "word" 变成 'word'

# 删除包围符号
ds"     -> "word" 变成 word
```

#### 3. 快速跳转技巧

```text
# 跳转到指定字符
s + t   -> 跳转到下一个 't'

# 语法树跳转
S       -> 智能跳转到语法元素
```

## 🔧 故障排除

### 常见问题

#### 1. 插件无法加载

**症状**: 启动时出现插件错误

**解决方案**:

```powershell
# 检查 Neovim 版本
nvim --version

# 重新安装 lazy.nvim
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\nvim-data\lazy"
```

#### 2. VSCode 命令无法执行

**症状**: 按键无响应或报错

**解决方案**:

1. 确保 VSCode Neovim 插件已启用
2. 检查 VSCode 设置中的 Neovim 路径
3. 重启 VSCode

#### 3. 键位冲突

**症状**: 某些键位不工作

**解决方案**:

1. 检查 VSCode 键位绑定设置
2. 在 VSCode 设置中禁用冲突的键位
3. 修改配置文件中的键位映射

#### 4. 性能问题

**症状**: 编辑器响应缓慢

**解决方案**:

1. 减少插件数量
2. 使用 `event = 'VeryLazy'` 延迟加载
3. 检查插件配置是否合理

### 配置验证

```powershell
# 检查配置文件语法
nvim --headless -c "luafile $env:LOCALAPPDATA\nvim\init.lua" -c "qa"

# 查看插件状态
nvim -c "Lazy" -c "qa"
```

### 日志调试

```lua
-- 在配置文件中添加调试信息
vim.notify("Config loaded successfully", vim.log.levels.INFO)

-- 检查插件是否加载
if pcall(require, 'flash') then
  vim.notify("Flash plugin loaded", vim.log.levels.INFO)
else
  vim.notify("Flash plugin failed to load", vim.log.levels.ERROR)
end
```

## 📖 详细文档

为了更好地组织和维护文档，我们将详细的技术文档分离到 `docs/` 目录下：

- **[项目架构与核心原理](docs/architecture.md)** - 深入了解项目的设计理念、架构模式和核心原理
- **[插件使用指南](docs/plugins-guide.md)** - 每个插件的详细配置说明、使用技巧和最佳实践

这些文档提供了比本 README 更深入的技术细节和使用指导。

## 📚 参考资源

### 官方文档

- [VSCode Neovim 插件文档](https://github.com/vscode-neovim/vscode-neovim)
- [Neovim 官方文档](https://neovim.io/doc/)
- [Lazy.nvim 文档](https://lazy.folke.io/)

### 插件文档

- [Flash.nvim 文档](https://github.com/folke/flash.nvim)
- [nvim-surround 文档](https://github.com/kylechui/nvim-surround)
- [Comment.nvim 文档](https://github.com/numToStr/Comment.nvim)
- [mini.ai 文档](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-ai.md)
- [Telescope.nvim 文档](https://github.com/nvim-telescope/telescope.nvim)
- [nvim-treesitter 文档](https://github.com/nvim-treesitter/nvim-treesitter)
- [toggleterm.nvim 文档](https://github.com/akinsho/toggleterm.nvim)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个配置！

### 贡献指南

1. Fork 本项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 📄 许可证

MIT License - 详见 LICENSE 文件

---

**享受你的 VSCode Neovim 体验！** 🎉
