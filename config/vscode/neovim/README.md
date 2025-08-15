# VSCode Neovim 配置指南

## 📋 目录

- [简介](#简介)
- [安装指南](#安装指南)
- [插件介绍](#插件介绍)
- [键位映射](#键位映射)
- [使用说明](#使用说明)
- [故障排除](#故障排除)

## 🎯 简介

这是一个专门为 VSCode Neovim 插件设计的配置文件，旨在：

- ✅ 增强 VSCode 中的 Vim 编辑体验
- ✅ 提供强大的文本操作功能
- ✅ 与 VSCode 功能完美集成
- ✅ 避免与 VSCode 原生功能冲突
- ✅ 保持轻量级和高性能

## 🚀 安装指南

### 前置要求

1. **安装 VSCode Neovim 插件**

   ```
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

1. **使用提供的 PowerShell 脚本**

   ```powershell
   # 在当前目录运行脚本
   .\setup-neovim-config.ps1
   
   # 或指定源文件路径
   .\setup-neovim-config.ps1 -SourceConfig "path\to\vscode_init.lua"
   
   # 强制覆盖现有配置
   .\setup-neovim-config.ps1 -Force
   ```

2. **手动安装**

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

```
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

```
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

```
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

   ```
   <leader>ff  -> 快速打开文件
   <leader>fg  -> 全局搜索内容
   <leader>fs  -> 搜索符号
   ```

2. **代码编辑**

   ```
   s + 字符     -> 快速跳转
   ys + 动作 + 符号 -> 添加包围符号
   gcc         -> 切换注释
   gr + 动作    -> 替换文本
   ```

3. **代码导航**

   ```
   gd          -> 跳转到定义
   gr          -> 查看引用
   gi          -> 跳转到实现
   ```

4. **界面管理**

   ```
   <leader>e   -> 切换文件树
   <leader>t   -> 切换终端
   <leader>g   -> 切换 Git 面板
   ```

### 高级技巧

#### 1. 文本对象组合

```
daf    -> 删除整个函数
vif    -> 选择函数内容
cio    -> 修改代码块内容
yao    -> 复制整个代码块
```

#### 2. 包围符号操作

```
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

```
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

## 📚 参考资源

- [VSCode Neovim 插件文档](https://github.com/vscode-neovim/vscode-neovim)
- [Lazy.nvim 文档](https://lazy.folke.io/)
- [Flash.nvim 文档](https://github.com/folke/flash.nvim)
- [nvim-surround 文档](https://github.com/kylechui/nvim-surround)
- [Comment.nvim 文档](https://github.com/numToStr/Comment.nvim)
- [mini.ai 文档](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-ai.md)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个配置！

## 📄 许可证

MIT License - 详见 LICENSE 文件

---

**享受你的 VSCode Neovim 体验！** 🎉
