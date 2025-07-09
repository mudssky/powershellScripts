# PSUtils - PowerShell 实用工具模块

一个功能丰富的 PowerShell 模块，提供各种实用函数和工具，简化日常 PowerShell 开发和系统管理任务。

## 📋 目录

- [模块概述](#模块概述)
- [安装和使用](#安装和使用)
- [功能模块](#功能模块)
  - [环境变量管理 (env)](#环境变量管理-env)
  - [字符串处理 (string)](#字符串处理-string)
  - [操作系统检测 (os)](#操作系统检测-os)
  - [网络工具 (network)](#网络工具-network)
  - [模块安装管理 (install)](#模块安装管理-install)
  - [通用函数 (functions)](#通用函数-functions)
  - [错误处理 (error)](#错误处理-error)
  - [FFmpeg 工具 (ffmpeg)](#ffmpeg-工具-ffmpeg)
  - [字体管理 (font)](#字体管理-font)
  - [硬件信息 (hardware)](#硬件信息-hardware)
  - [Linux 工具 (linux)](#linux-工具-linux)
  - [代理设置 (proxy)](#代理设置-proxy)
  - [PowerShell 工具 (pwsh)](#powershell-工具-pwsh)
  - [测试工具 (test)](#测试工具-test)
  - [Windows 工具 (win)](#windows-工具-win)
- [测试](#测试)
- [版本信息](#版本信息)

## 🚀 模块概述

PSUtils 是一个模块化的 PowerShell 工具集，包含 15 个功能模块，涵盖了环境管理、字符串处理、系统检测、网络工具等多个方面。每个模块都经过精心设计，提供简洁易用的 API 和完整的帮助文档。

### 主要特性

- 🔧 **模块化设计**: 15 个独立功能模块，按需加载
- 📚 **完整文档**: 每个函数都包含详细的帮助文档
- 🧪 **单元测试**: 使用 Pester 框架进行全面测试
- 🔄 **跨平台**: 支持 Windows、Linux 和 macOS
- 🛡️ **错误处理**: 完善的错误处理和异常管理
- 📦 **易于安装**: 标准 PowerShell 模块格式

## 🛠️ 安装和使用

### 安装模块

```powershell
# 导入模块
Import-Module .\psutils\psutils.psd1

# 或者从模块路径导入
Import-Module "C:\path\to\psutils"
```

### 基本使用

```powershell
# 查看所有可用函数
Get-Command -Module psutils

# 获取函数帮助
Get-Help Get-OperatingSystem -Full

# 使用函数
$os = Get-OperatingSystem
Write-Host "当前操作系统: $os"
```

## 📦 功能模块

### 🌍 环境变量管理 (env)

提供 .env 文件处理和环境变量管理功能。

#### 主要函数

- **`Get-Dotenv`**: 解析 .env 文件为键值对
- **`Install-Dotenv`**: 加载 .env 文件到环境变量

#### 使用示例

```powershell
# 解析 .env 文件
$envVars = Get-Dotenv -Path ".env"

# 加载环境变量
Install-Dotenv -Path ".env"
```

### 🔤 字符串处理 (string)

提供字符串处理和文本分析功能。

#### 主要函数

- **`Get-LineBreak`**: 检测字符串中的换行符类型

#### 使用示例

```powershell
# 检测换行符类型
$content = "Hello`r`nWorld"
$lineBreak = Get-LineBreak -Content $content
Write-Host "检测到换行符: $($lineBreak -eq "`r`n" ? 'CRLF' : 'LF')"
```

### 💻 操作系统检测 (os)

提供跨平台的操作系统检测功能。

#### 主要函数

- **`Get-OperatingSystem`**: 检测当前操作系统类型

#### 使用示例

```powershell
# 检测操作系统
$os = Get-OperatingSystem
switch ($os) {
    "Windows" { Write-Host "运行在 Windows 系统" }
    "Linux"   { Write-Host "运行在 Linux 系统" }
    "macOS"   { Write-Host "运行在 macOS 系统" }
    default   { Write-Host "未知操作系统: $os" }
}
```

### 🌐 网络工具 (network)

提供网络连接测试和端口检查功能。

#### 主要函数

- **`Test-PortOccupation`**: 检查端口是否被占用
- **`Wait-ForURL`**: 等待 URL 可访问

#### 使用示例

```powershell
# 检查端口占用
if (Test-PortOccupation -Port 8080) {
    Write-Host "端口 8080 已被占用"
} else {
    Write-Host "端口 8080 可用"
}

# 等待服务启动
Wait-ForURL -URL "http://localhost:8080" -Timeout 30
```

### 📦 模块安装管理 (install)

提供 PowerShell 模块安装和管理功能。

#### 主要函数

- **`Test-ModuleInstalled`**: 检测模块是否已安装
- **`Install-RequiredModule`**: 安装所需模块

#### 使用示例

```powershell
# 检查模块是否安装
if (Test-ModuleInstalled -ModuleName "Pester") {
    Write-Host "Pester 模块已安装"
}

# 安装必需模块
Install-RequiredModule -ModuleNames @("Pester", "PSReadLine")
```

### 🔧 通用函数 (functions)

提供各种通用工具函数。

#### 主要函数

- **`Get-HistoryCommandRank`**: 获取命令使用频率排行
- **`Get-ScriptFolder`**: 获取脚本执行目录
- **`Start-Ipython`**: 启动 IPython
- **`Start-PSReadline`**: 配置 PSReadLine
- **`New-Shortcut`**: 创建快捷方式

#### 使用示例

```powershell
# 查看命令使用排行
Get-HistoryCommandRank -top 20

# 获取脚本目录
$scriptDir = Get-ScriptFolder

# 创建快捷方式
New-Shortcut -Path "C:\Program Files\App\app.exe" -Destination "C:\Users\Desktop\App.lnk"
```

### ⚠️ 错误处理 (error)

提供统一的错误处理和异常管理功能。

### 🎬 FFmpeg 工具 (ffmpeg)

提供 FFmpeg 相关的媒体处理工具。

### 🔤 字体管理 (font)

提供系统字体管理功能。

### 🖥️ 硬件信息 (hardware)

提供硬件信息查询功能。

### 🐧 Linux 工具 (linux)

提供 Linux 系统专用工具。

### 🌐 代理设置 (proxy)

提供网络代理配置管理功能。

### 💻 PowerShell 工具 (pwsh)

提供 PowerShell 环境增强功能。

### 🧪 测试工具 (test)

提供测试和验证相关的工具函数。

### 📖 帮助搜索 (help)

提供高性能的模块内帮助搜索功能，替代传统Get-Help的模块搜索。

#### 主要函数

- **`Search-ModuleHelp`**: 在指定模块或路径中搜索函数帮助信息
- **`Find-PSUtilsFunction`**: 快速搜索当前psutils模块中的函数
- **`Get-FunctionHelp`**: 获取指定函数的详细帮助信息

#### 使用示例

```powershell
# 搜索包含"install"关键词的函数
Find-PSUtilsFunction "install"

# 获取特定函数的详细帮助
Get-FunctionHelp "Get-OperatingSystem"

# 在指定路径中搜索函数
Search-ModuleHelp -SearchTerm "config" -ModulePath "C:\MyModule"

# 显示详细信息
Find-PSUtilsFunction "Get" -ShowDetails
```

#### 性能优势

- 只搜索指定模块，避免全局扫描
- 直接解析文件，无需模块加载开销
- 支持模糊搜索和精确匹配
- 提供更好的输出格式和颜色显示

### 🪟 Windows 工具 (win)

提供 Windows 系统专用工具。

## 🧪 测试

模块包含完整的单元测试，使用 Pester 框架。

```powershell
# 运行所有测试
Invoke-Pester .\tests\

# 运行特定模块测试
Invoke-Pester .\tests\string.Tests.ps1
```

### 测试覆盖

- ✅ 环境变量管理
- ✅ 字符串处理
- ✅ 操作系统检测
- ✅ 模块安装管理
- ✅ 通用函数
- ✅ 错误处理
- ✅ 字体管理
- ✅ 测试工具

## 📋 版本信息

- **版本**: 0.0.1
- **作者**: mudssky
- **许可**: All rights reserved
- **PowerShell 版本**: 5.1+
- **平台支持**: Windows, Linux, macOS

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个模块。

### 开发指南

1. 每个新功能都应该添加到相应的模块文件中
2. 为新函数编写完整的帮助文档
3. 添加相应的单元测试
4. 确保跨平台兼容性

## 📚 更多信息

- 查看各个模块的源代码以了解详细实现
- 使用 `Get-Help` 命令获取函数的详细帮助
- 参考测试文件了解使用示例

---

*PSUtils - 让 PowerShell 开发更简单* 🚀
