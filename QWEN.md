# PowerShell Scripts Collection - 项目上下文说明

## 项目概述

这是一个功能丰富的 PowerShell 脚本集合，提供各种实用工具和自动化解决方案。项目旨在提供日常工作和系统管理中常用的自动化工具，涵盖了媒体处理、系统管理、开发辅助、文件操作等多个领域。

### 主要特性

- **模块化设计**: 每个脚本都是独立的功能模块
- **详细文档**: 每个脚本都包含完整的帮助文档
- **安全可靠**: 包含权限检查和错误处理
- **备份恢复**: 重要操作支持备份和恢复功能
- **易于使用**: 提供丰富的参数和使用示例

### 核心组件

1. **PSUtils 模块**: 一个功能丰富的 PowerShell 实用工具模块，包含 15 个功能模块，涵盖环境管理、字符串处理、系统检测、网络工具等多个方面。
2. **脚本执行器**: 类似 npm scripts 的命令执行器，支持 pre/post 钩子、多种项目模板、自动 Node.js 版本切换等功能。
3. **环境变量管理**: 提供 PATH 环境变量清理和恢复功能。
4. **媒体处理工具**: 包括 FFmpeg 视频压制预设、视频转音频、FLV 文件合并、DVD 视频压缩、音频转换、图像压缩等工具。
5. **系统管理工具**: 包括小文件清理、文件夹大小计算、文件名合法化、丢失数字序列查找、配置文件同步、代理设置助手等工具。
6. **开发工具**: 包括代码检查、Pester 测试配置、Git 配置、VS Code 配置工具等。
7. **网络和下载工具**: 包括 GitHub 仓库下载、通用下载工具等。

## 项目结构

```
powershellScripts/
├── psutils/                 # PSUtils 通用工具模块
│   ├── modules/             # 功能模块
│   ├── tests/               # 单元测试
│   └── README.md            # PSUtils 模块文档
├── profile/                 # PowerShell 配置文件
├── config/                  # 配置文件
├── templates/               # 脚本模板
├── docs/                    # 文档和速查表
├── ai/                      # AI 相关工具
├── linux/                   # Linux 特定脚本
├── macos/                   # macOS 特定脚本
├── deprecated/              # 已弃用的脚本
├── .trae/                   # Trae 配置
├── .vscode/                 # VS Code 配置
└── *.ps1                    # 主要脚本文件
```

## 核心脚本说明

### 系统环境管理

#### cleanEnvPath.ps1
清理 PATH 环境变量中的无效路径，包括不存在的目录、无可执行文件的目录、重复路径以及 User PATH 与 System PATH 的重复项。

#### restoreEnvPath.ps1
从备份文件恢复 PATH 环境变量。

### 脚本执行器

#### runScripts.ps1
类似 npm scripts 的命令执行器，支持多种项目模板（golang, rust, nodejs）、pre/post 钩子、自动 Node.js 版本切换、全局脚本配置。

#### install.ps1
项目安装和初始化脚本，检查管理员权限、安装必要的 PowerShell 模块、创建符号链接、加载配置文件。

### 媒体处理工具

#### ffmpegPreset.ps1
FFmpeg 视频压制预设工具，提供多种预设选项如 720p、480p、H.265 编码等。

#### VideoToAudio.ps1
视频转音频工具。

#### concatflv.ps1
FLV 文件合并工具。

#### dvdcompress.ps1
DVD 视频压缩工具。

#### losslessToQaac.ps1
无损音频转 AAC 格式。

#### pngCompress.ps1
PNG 图片压缩工具。

#### webpCompress.ps1
WebP 图片压缩工具。

### 系统管理工具

#### smallFileCleaner.ps1
清理小文件工具，可指定文件大小阈值。

#### folderSize.ps1
计算文件夹大小。

#### renameLegal.ps1
文件名合法化工具。

#### findLostNum.ps1
查找丢失的数字序列。

#### syncConfig.ps1
配置文件同步工具，支持备份和恢复。

#### proxyHelper.ps1
代理设置助手。

### 开发工具

#### pslint.ps1
PowerShell 代码检查工具。

#### PesterConfiguration.ps1
Pester 测试配置。

#### gitconfig_personal.ps1
Git 个人配置设置。

#### Setup-VSCodeSSH.ps1
VS Code SSH 配置工具。

#### DownloadVSCodeExtension.ps1
VS Code 扩展下载工具。

#### get-SnippetsBody.ps1
代码片段提取工具。

## PSUtils 模块

PSUtils 是一个功能丰富的 PowerShell 实用工具模块，提供各种常用函数和工具。

### 主要功能模块

- **环境变量管理 (env)**: .env 文件处理和环境变量操作
- **字符串处理 (string)**: 文本分析和字符串工具
- **操作系统检测 (os)**: 跨平台系统识别
- **网络工具 (network)**: 端口检查和连接测试
- **缓存管理 (cache)**: 函数结果缓存功能
- **模块安装管理 (install)**: PowerShell 模块安装和检测
- **通用函数 (functions)**: 命令历史、快捷方式创建等实用工具
- **错误处理 (error)**: 统一的异常管理
- **FFmpeg 工具 (ffmpeg)**: FFmpeg 相关功能
- **字体管理 (font)**: 字体相关功能
- **硬件信息 (hardware)**: 硬件信息查询
- **Linux 工具 (linux)**: Linux 系统专用工具
- **代理设置 (proxy)**: 网络代理配置管理
- **PowerShell 工具 (pwsh)**: PowerShell 环境增强功能
- **测试工具 (test)**: 测试和验证相关的工具函数
- **帮助搜索 (help)**: 高性能的模块内帮助搜索功能

## 开发规范

### 代码风格规范

- **函数命名**: 使用 Pascal 命名法（如 `Install-RequiredModule`）
- **参数命名**: 使用 Pascal 命名法（如 `$ModuleName`）
- **变量命名**: 使用 camelCase 命名法（如 `$appName`）
- **缩进**: 使用 4 个空格进行缩进
- **注释**: 使用中文进行注释，函数必须包含完整的 PowerShell Help 注释

### 测试规范

- 使用 Pester 框架进行单元测试
- 测试文件以 `.Tests.ps1` 结尾
- 测试覆盖主要功能和边界情况
- 支持并行测试

### 文档规范

- 每个脚本都包含详细的帮助文档
- 提供参数说明和使用示例
- README 文件提供完整的使用说明

## 构建和运行

### 安装依赖

```powershell
# 运行安装脚本
.\install.ps1
```

### 执行脚本

```powershell
# 执行单个脚本
.\scriptName.ps1 -Parameter value

# 使用脚本执行器
.\runScripts.ps1 -CommandName command
```

### 运行测试

```powershell
# 运行所有测试
.\runScripts.ps1 -CommandName test

# 或直接运行
pwsh -Command "Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )"
```

### 代码格式化

```powershell
# 格式化 PowerShell 代码
.\runScripts.ps1 -CommandName format

# 或直接运行
pwsh -File ./scripts/Format-PowerShellCode.ps1 -Path . -Recurse
```

## 贡献指南

1. **文档**: 每个脚本必须包含完整的帮助文档
2. **参数**: 使用 `[CmdletBinding()]` 和适当的参数验证
3. **错误处理**: 包含适当的错误处理和用户提示
4. **测试**: 为新功能编写 Pester 测试
5. **代码规范**: 遵循项目中的代码风格规范

## 环境要求

- Windows PowerShell 5.1 或 PowerShell Core 6.0+
- 部分功能需要管理员权限
- 某些脚本需要额外的依赖模块（如 Pester）

## 注意事项

- 使用这些脚本前请仔细阅读每个脚本的帮助文档
- 某些操作可能会修改系统配置或删除文件
- 建议在测试环境中先行验证