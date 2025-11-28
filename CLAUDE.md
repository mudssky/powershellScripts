# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个功能丰富的 PowerShell 脚本集合，提供各种实用工具和自动化解决方案。项目包含：
- **PSUtils 模块**: 核心 PowerShell 实用工具模块，提供 15 个功能模块
- **核心脚本**: 系统环境管理、脚本执行器、配置文件同步等
- **媒体处理工具**: FFmpeg 预设、音视频转换、图片压缩等
- **系统管理工具**: 文件清理、环境变量管理、代理设置等
- **开发工具**: 代码格式化、测试、Git 配置等

## 常用命令

### 环境设置和安装
```powershell
# 运行安装脚本，安装必要的模块和依赖
.\install.ps1

# 初始化项目脚本配置（类似 npm scripts）
.\runScripts.ps1 -init -TemplateName golang

# 启用全局脚本配置
.\runScripts.ps1 -CommandName build -enableGlobalScripts
```

### 测试
```powershell
# 运行所有测试
pnpm test

# 运行详细测试输出
pnpm test:detailed

# 使用 Pester 配置运行测试
pwsh -Command "Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )"
```

### 代码格式化和质量检查
```powershell
# 格式化 PowerShell 代码
pnpm format:pwsh

# 格式化 JavaScript/TypeScript 代码
pnpm format:biome

# 格式化所有代码
pnpm format

# 运行 lint-staged（通常在 git commit 时自动执行）
pnpm lint-staged
```

### 环境变量管理
```powershell
# 清理 PATH 环境变量中的无效路径
.\cleanEnvPath.ps1

# 清理系统级 PATH（需要管理员权限）
.\cleanEnvPath.ps1 -EnvTarget Machine

# 预览清理操作
.\cleanEnvPath.ps1 -WhatIf

# 从备份恢复 PATH
.\restoreEnvPath.ps1 -BackupFilePath "C:\backup\PATH_User_20231201_143022.txt"
```

### 媒体处理
```powershell
# 使用 FFmpeg 预设压制视频
.\ffmpegPreset.ps1 -path 'input.flv' -preset '720p28'

# 批量处理视频
ls *.flv | % { .\ffmpegPreset.ps1 -path $_.Name }

# 视频转音频
.\VideoToAudio.ps1 -InputFile 'video.mp4' -OutputFormat 'mp3'
```

## 核心模块：PSUtils

PSUtils 是项目的核心模块，提供 15 个功能模块：

```powershell
# 导入 PSUtils 模块
Import-Module .\psutils\psutils.psd1

# 查看所有可用函数
Get-Command -Module psutils

# 搜索模块内函数
Find-PSUtilsFunction "install" -ShowDetails

# 使用缓存功能提升性能
$result = Invoke-WithCache -Key "expensive-operation" -ScriptBlock {
    # 耗时操作
    Get-Process | Select-Object -First 10
}
```

### 主要功能模块
- **env**: .env 文件处理和环境变量管理
- **string**: 字符串处理和文本分析
- **os**: 跨平台操作系统检测
- **network**: 网络连接测试、端口检查
- **cache**: 高性能函数结果缓存
- **install**: PowerShell 模块安装管理
- **functions**: 通用工具函数
- **help**: 模块内帮助搜索

## 项目架构

### 目录结构
```
powershellScripts/
├── psutils/                    # 核心工具模块
│   ├── modules/               # 15个功能模块文件
│   ├── tests/                 # 单元测试文件
│   ├── examples/              # 使用示例
│   └── demo/                 # 演示脚本
├── scripts/                   # 构建和工具脚本
├── profile/                   # PowerShell 配置文件
├── config/                    # 配置文件和设置
├── ai/                        # AI 相关工具
├── linux/                     # Linux 特定脚本
├── macos/                     # macOS 特定脚本
├── deprecated/                # 已弃用的脚本
├── templates/                 # 脚本模板
└── *.ps1                      # 主要功能脚本
```

### 构建系统
- **包管理**: 使用 pnpm 作为包管理器
- **代码格式化**:
  - PowerShell: 使用 PSScriptAnalyzer 的 Invoke-Formatter
  - JavaScript/TypeScript: 使用 Biome
- **测试框架**: Pester，配置文件为 `PesterConfiguration.ps1`
- **Git 钩子**: 使用 Husky 和 lint-staged

### 配置文件
- **biome.json**: Biome 格式化配置
- **PesterConfiguration.ps1**: Pester 测试配置
- **lint-staged.config.js**: 代码提交前的检查配置

## 开发指南

### 脚本开发规范
1. **文档**: 每个脚本必须包含完整的帮助文档（.SYNOPSIS, .DESCRIPTION, .EXAMPLE, .NOTES）
2. **参数**: 使用 `[CmdletBinding()]` 和适当的参数验证
3. **错误处理**: 包含适当的错误处理和用户提示
4. **测试**: 为新功能编写 Pester 测试

### 添加新功能
1. 在 `psutils/modules/` 中添加功能到相应模块
2. 在 `psutils/tests/` 中添加单元测试
3. 更新相关文档和示例
4. 运行测试确保功能正常

### 脚本执行器使用
项目包含类似 npm scripts 的脚本执行器：

```powershell
# 初始化项目脚本
.\runScripts.ps1 -init -TemplateName golang

# 执行定义的命令
.\runScripts.ps1 -CommandName test

# 列出所有可用命令
.\runScripts.ps1 -listCommands

# 支持预/后钩子（如 pretest -> test -> posttest）
```

## 测试和质量保证

### 运行测试
```powershell
# 运行所有测试
pnpm test

# 运行特定模块测试
Invoke-Pester .\psutils\tests\cache.Tests.ps1

# 生成测试结果报告
pwsh -Command "Invoke-Pester -Output Detailed"
```

### 代码质量
- 所有 PowerShell 代码使用 PSScriptAnalyzer 进行静态分析
- 支持 lint-staged 进行提交前检查
- 代码覆盖率分析（排除特定模块）
- 并行测试执行（最多4个线程）

## 性能优化

### 缓存系统
PSUtils 提供高性能的缓存功能：

```powershell
# 使用缓存减少重复计算
$result = Invoke-WithCache -Key "data" -ScriptBlock { Get-Service }

# 不同缓存类型
$xmlResult = Invoke-WithCache -Key "data" -CacheType XML -ScriptBlock { @{Object} }
$textResult = Invoke-WithCache -Key "data" -CacheType Text -ScriptBlock { "String" }

# 缓存管理
Get-CacheStats -Detailed
Clear-ExpiredCache
```

## 跨平台支持

- **Windows**: 主要支持平台，提供完整的 Windows 特定功能
- **Linux**: 提供基本的 Linux 支持和 WSL2 配置
- **macOS**: 提供安装脚本和配置管理

## 故障排除

### 执行策略问题
```powershell
# 临时绕过执行策略
powershell -ExecutionPolicy Bypass -File .\scriptName.ps1

# 设置执行策略（管理员权限）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 模块安装问题
```powershell
# 安装必需的 PowerShell 模块
Install-Module -Name Pester -Scope CurrentUser
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
```

### 权限问题
- 某些脚本需要管理员权限（如系统级环境变量修改）
- 使用 `-WhatIf` 参数预览操作
- 重要操作会自动创建备份