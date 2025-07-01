# PowerShell Scripts Collection

一个功能丰富的 PowerShell 脚本集合，提供各种实用工具和自动化解决方案。

## 📋 目录

- [项目概述](#项目概述)
- [安装和设置](#安装和设置)
- [核心脚本](#核心脚本)
- [媒体处理工具](#媒体处理工具)
- [系统管理工具](#系统管理工具)
- [开发工具](#开发工具)
- [网络和下载工具](#网络和下载工具)
- [文件管理工具](#文件管理工具)
- [配置和环境](#配置和环境)
- [使用说明](#使用说明)
- [贡献指南](#贡献指南)

## 🚀 项目概述

本项目是一个综合性的 PowerShell 脚本库，旨在提供各种日常工作和系统管理中常用的自动化工具。脚本涵盖了媒体处理、系统管理、开发辅助、文件操作等多个领域。

### 主要特性

- 🔧 **模块化设计**: 每个脚本都是独立的功能模块
- 📚 **详细文档**: 每个脚本都包含完整的帮助文档
- 🛡️ **安全可靠**: 包含权限检查和错误处理
- 🔄 **备份恢复**: 重要操作支持备份和恢复功能
- 🎯 **易于使用**: 提供丰富的参数和使用示例

## 🛠️ 安装和设置

### 快速开始

```powershell
# 克隆项目
git clone <repository-url>
cd powershellScripts

# 运行安装脚本
.\install.ps1
```

### 系统要求

- Windows PowerShell 5.1 或 PowerShell Core 6.0+
- 部分功能需要管理员权限
- 某些脚本需要额外的依赖模块（如 Pester）

## 📦 核心脚本

### 🔧 系统环境管理

#### `cleanEnvPath.ps1`
**功能**: 清理 PATH 环境变量中的无效路径

```powershell
# 清理用户级 PATH
.\cleanEnvPath.ps1

# 清理系统级 PATH（需要管理员权限）
.\cleanEnvPath.ps1 -EnvTarget Machine

# 预览清理操作
.\cleanEnvPath.ps1 -WhatIf

# 强制执行并指定备份路径
.\cleanEnvPath.ps1 -Force -BackupPath "C:\Backup"
```

**特性**:
- 自动检测无效路径（不存在的目录、无可执行文件的目录）
- 移除重复路径
- 检测用户 PATH 与系统 PATH 的重复项
- 自动备份原始配置
- 支持 WhatIf 预览模式

#### `restoreEnvPath.ps1`
**功能**: 从备份文件恢复 PATH 环境变量

```powershell
# 从指定备份文件恢复
.\restoreEnvPath.ps1 -BackupFilePath "C:\backup\PATH_User_20231201_143022.txt"

# 从备份目录选择恢复
.\restoreEnvPath.ps1 -BackupDirectory "C:\backup" -EnvTarget User
```

### 🏃‍♂️ 脚本执行器

#### `runScripts.ps1`
**功能**: 类似 npm scripts 的命令执行器

```powershell
# 执行指定命令
.\runScripts.ps1 -CommandName test

# 列出所有可用命令
.\runScripts.ps1 -listCommands

# 初始化配置文件
.\runScripts.ps1 -init -TemplateName golang

# 启用全局配置
.\runScripts.ps1 -CommandName build -enableGlobalScripts
```

**特性**:
- 支持 pre/post 钩子
- 多种项目模板（golang, rust, nodejs）
- 自动 Node.js 版本切换
- 全局脚本配置支持

#### `install.ps1`
**功能**: 项目安装和初始化脚本

```powershell
.\install.ps1
```

**功能**:
- 检查管理员权限
- 安装必要的 PowerShell 模块（如 Pester）
- 创建符号链接
- 加载配置文件

## 🎬 媒体处理工具

### 视频处理

#### `ffmpegPreset.ps1`
**功能**: FFmpeg 视频压制预设工具

```powershell
# 基本压制
.\ffmpegPreset.ps1 -path 'input.flv'

# 使用预设
.\ffmpegPreset.ps1 -preset '720p28' -path 'input.flv'

# 批量处理
ls *.flv | % { .\ffmpegPreset.ps1 -path $_.Name }
```

**预设选项**:
- `720p`: 720p 30fps H.264 编码
- `720p28`: 720p 30fps H.264 CRF28
- `480p`: 480p 30fps H.264 编码
- `x265`: H.265 编码
- `hevc`: H.265 CRF28 编码

#### `VideoToAudio.ps1`
**功能**: 视频转音频工具

#### `concatflv.ps1`
**功能**: FLV 文件合并工具

#### `dvdcompress.ps1`
**功能**: DVD 视频压缩工具

### 音频处理

#### `losslessToQaac.ps1`
**功能**: 无损音频转 AAC 格式

### 图像处理

#### `pngCompress.ps1`
**功能**: PNG 图片压缩工具

#### `webpCompress.ps1`
**功能**: WebP 图片压缩工具

## 🖥️ 系统管理工具

### 文件管理

#### `smallFileCleaner.ps1`
**功能**: 清理小文件工具

```powershell
# 清理小于 10KB 的文件
.\smallFileCleaner.ps1 -limitedSize 10kb

# 仅列出不删除
.\smallFileCleaner.ps1 -limitedSize 10kb -noDelete
```

#### `folderSize.ps1`
**功能**: 计算文件夹大小

```powershell
# 计算当前目录大小
.\folderSize.ps1

# 计算指定目录大小
.\folderSize.ps1 -path "C:\SomeFolder"
```

#### `renameLegal.ps1`
**功能**: 文件名合法化工具

#### `findLostNum.ps1`
**功能**: 查找丢失的数字序列

### 系统配置

#### `syncConfig.ps1`
**功能**: 配置文件同步工具

```powershell
# 备份配置
.\syncConfig.ps1 -Mode backup

# 恢复配置
.\syncConfig.ps1 -Mode restore

# 列出配置
.\syncConfig.ps1 -Mode list
```

#### `proxyHelper.ps1`
**功能**: 代理设置助手

```powershell
# 为 Git 设置代理
.\proxyHelper.ps1 -SetProxyProgram git

# 取消 Git 代理
.\proxyHelper.ps1 -UnsetProxyProgram git
```

## 🔧 开发工具

### 代码质量

#### `pslint.ps1`
**功能**: PowerShell 代码检查工具

#### `PesterConfiguration.ps1`
**功能**: Pester 测试配置

### 版本控制

#### `gitconfig_personal.ps1`
**功能**: Git 个人配置设置

### IDE 和编辑器

#### `Setup-VSCodeSSH.ps1`
**功能**: VS Code SSH 配置工具

#### `DownloadVSCodeExtension.ps1`
**功能**: VS Code 扩展下载工具

#### `get-SnippetsBody.ps1`
**功能**: 代码片段提取工具

## 🌐 网络和下载工具

#### `downGithub.ps1`
**功能**: GitHub 仓库下载工具

#### `downWith.ps1`
**功能**: 通用下载工具

## 📁 文件格式处理

#### `ExtractAss.ps1`
**功能**: ASS 字幕文件提取

#### `concatXML.ps1`
**功能**: XML 文件合并

#### `ConventAllbyExt.ps1`
**功能**: 按扩展名批量转换文件

## 🐳 容器和服务

#### `start-container.ps1`
**功能**: 容器启动工具

#### `Start-Bee.ps1`
**功能**: Bee 服务启动工具

## 📊 数据处理

#### `jupyconvert.ps1`
**功能**: Jupyter Notebook 转换工具

#### `tesseract.ps1`
**功能**: OCR 文字识别工具

## 🧹 清理工具

#### `cleanTorrent.ps1`
**功能**: 种子文件清理工具

#### `dlsiteUpdate.ps1`
**功能**: DLsite 更新工具

## 📚 使用说明

### 获取帮助

每个脚本都包含详细的帮助信息：

```powershell
# 查看脚本帮助
Get-Help .\scriptName.ps1 -Full

# 查看参数说明
Get-Help .\scriptName.ps1 -Parameter *

# 查看使用示例
Get-Help .\scriptName.ps1 -Examples
```

### 执行策略

如果遇到执行策略限制，可以临时设置：

```powershell
# 设置执行策略（管理员权限）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 或者绕过执行策略
powershell -ExecutionPolicy Bypass -File .\scriptName.ps1
```

### 模块依赖

项目包含 `psutils` 模块，提供通用功能：

```powershell
# 导入模块
Import-Module "$PSScriptRoot\psutils" -Force
```

## 🤝 贡献指南

### 代码规范

1. **文档**: 每个脚本必须包含完整的帮助文档
2. **参数**: 使用 `[CmdletBinding()]` 和适当的参数验证
3. **错误处理**: 包含适当的错误处理和用户提示
4. **测试**: 为新功能编写 Pester 测试

### 提交规范

- 使用清晰的提交信息
- 遵循现有的代码风格
- 更新相关文档

### 目录结构

```
powershellScripts/
├── psutils/                 # 通用工具模块
├── profile/                 # PowerShell 配置文件
├── config/                  # 配置文件
├── templates/               # 脚本模板
├── ai/                      # AI 相关工具
├── linux/                   # Linux 特定脚本
├── macos/                   # macOS 特定脚本
├── deprecated/              # 已弃用的脚本
├── .trae/                   # Trae 配置
├── .vscode/                 # VS Code 配置
└── *.ps1                    # 主要脚本文件
```

## 📄 许可证

本项目采用 [LICENSE](LICENSE) 许可证。

## 🔗 相关链接

- [PowerShell 官方文档](https://docs.microsoft.com/powershell/)
- [Pester 测试框架](https://pester.dev/)
- [FFmpeg 文档](https://ffmpeg.org/documentation.html)

---

**注意**: 使用这些脚本前请仔细阅读每个脚本的帮助文档，某些操作可能会修改系统配置或删除文件。建议在测试环境中先行验证。