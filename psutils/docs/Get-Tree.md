# Get-Tree 函数文档

## 概述

`Get-Tree` 是一个PowerShell函数，用于以树状格式显示目录结构。它提供了类似于Unix `tree` 命令的功能，支持多种自定义选项。

## 功能特性

- 🌳 **树状显示**: 以直观的树状格式显示目录结构
- 🎨 **彩色输出**: 不同类型的文件和目录使用不同颜色显示
- 📁 **深度控制**: 可自定义显示的最大深度
- 🔍 **文件过滤**: 可选择是否显示文件，或排除特定文件
- 👁️ **隐藏文件**: 可选择是否显示隐藏文件和目录
- 📊 **数量限制**: 可限制每个目录显示的最大项目数
- 🚀 **跨平台**: 支持Windows、macOS和Linux

## 语法

```powershell
Get-Tree [[-Path] <String>] [-MaxDepth <Int32>] [-ShowFiles <Boolean>] [-ShowHidden <Boolean>] [-Exclude <String[]>] [-MaxItems <Int32>]
```

## 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Path` | String | "." | 要显示树状结构的目录路径 |
| `MaxDepth` | Int32 | 3 | 最大显示深度，-1表示无限深度 |
| `ShowFiles` | Boolean | $true | 是否显示文件 |
| `ShowHidden` | Boolean | $false | 是否显示隐藏文件和目录 |
| `Exclude` | String[] | @() | 要排除的文件或目录名称模式（支持通配符） |
| `MaxItems` | Int32 | 50 | 每个目录中显示的最大项目数 |

## 使用示例

### 基本用法

```powershell
# 显示当前目录的树状结构（默认3层深度）
Get-Tree

# 显示指定目录的树状结构
Get-Tree -Path "C:\Users"
```

### 控制显示深度

```powershell
# 显示2层深度
Get-Tree -MaxDepth 2

# 显示所有层级（无限深度）
Get-Tree -MaxDepth -1
```

### 只显示目录结构

```powershell
# 只显示目录，不显示文件
Get-Tree -ShowFiles $false
```

### 排除特定文件

```powershell
# 排除所有.tmp文件和node_modules目录
Get-Tree -Exclude @("*.tmp", "node_modules")

# 排除多种文件类型
Get-Tree -Exclude @("*.log", "*.tmp", "*.cache")
```

### 显示隐藏文件

```powershell
# 显示包括隐藏文件在内的所有文件
Get-Tree -ShowHidden $true
```

### 限制显示数量

```powershell
# 每个目录最多显示10个项目
Get-Tree -MaxItems 10
```

### 组合使用

```powershell
# 组合多个参数
Get-Tree -Path "./src" -MaxDepth 4 -ShowFiles $true -Exclude @("*.min.js", "node_modules") -MaxItems 20
```

## 颜色说明

- 🔵 **蓝色**: 目录
- ⚪ **白色**: 普通文件
- 🔘 **深灰色**: 隐藏文件
- 🟢 **绿色**: 可执行文件（.exe, .bat, .cmd, .ps1, .sh等）
- 🟡 **黄色**: 压缩文件（.zip, .rar, .7z等）

## 输出示例

```
C:\MyProject
├── src/
│   ├── components/
│   │   ├── Header.js
│   │   └── Footer.js
│   ├── utils/
│   │   └── helpers.js
│   └── index.js
├── tests/
│   └── app.test.js
├── package.json
└── README.md
```

## 注意事项

1. **权限**: 如果没有访问某个目录的权限，会显示警告信息但不会中断执行
2. **性能**: 对于包含大量文件的目录，建议使用 `MaxDepth` 和 `MaxItems` 参数来限制输出
3. **通配符**: `Exclude` 参数支持PowerShell通配符模式（如 `*`, `?`）
4. **路径**: 支持相对路径和绝对路径

## 安装和使用

1. 确保 `functions.psm1` 模块已加载：

   ```powershell
   Import-Module "path\to\functions.psm1"
   ```

2. 使用函数：

   ```powershell
   Get-Tree
   ```

3. 查看帮助：

   ```powershell
   Get-Help Get-Tree -Full
   ```

## 相关函数

- `Get-ChildItem`: PowerShell内置的目录列表函数
- `tree`: Windows/Unix系统的树状目录显示命令

---
