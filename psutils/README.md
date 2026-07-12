# PSUtils

PSUtils 是面向日常脚本、开发环境和系统管理的 PowerShell 工具模块。模块通过
manifest 聚合环境变量、配置解析、文件系统、网络、Docker、代理、缓存和平台工具。

## 运行要求

- PowerShell 7.4 或更高版本
- PowerShell Core edition
- Windows、Linux 或 macOS；部分命令只在对应平台生效

运行时版本和公共导出以 [`psutils.psd1`](./psutils.psd1) 为唯一事实来源。

## 导入模块

从仓库根目录导入规范 manifest：

```powershell
Import-Module ./psutils/psutils.psd1 -Force
```

也可以直接导入模块目录，PowerShell 会解析到同一个 manifest：

```powershell
Import-Module ./psutils -Force
```

`index.psm1` 仅用于兼容旧脚本，会输出弃用提示；新脚本和示例不应继续使用该入口。

## 查找命令和帮助

```powershell
# 浏览模块当前实际导出的命令
Get-Command -Module psutils | Sort-Object Noun, Verb

# 使用 PowerShell 标准帮助系统
Get-Help Get-Tree -Full
Get-Help Invoke-WithCache -Examples

# 按名称筛选模块命令
Get-Command -Module psutils -Name '*Config*'
```

旧的 `Search-ModuleHelp`、`Find-PSUtilsFunction` 和 `Get-FunctionHelp` 已弃用，当前仅为
兼容已有调用而保留。新代码应使用 `Get-Help` 和 `Get-Command`。

## 主要能力

以下分类只列出常用入口，不复制完整导出清单。完整列表请运行
`Get-Command -Module psutils`。

### 配置与环境变量

- `Resolve-ConfigSources`：按统一优先级合并配置来源
- `Read-ConfigEnvFile`、`Resolve-DefaultEnvFiles`：读取和发现 env 配置
- `Get-Dotenv`、`Install-Dotenv`：解析或加载 `.env` 文件
- `Invoke-WithScopedEnvironment`：在受控作用域内临时设置环境变量

### 文件系统与归档

- `Get-Tree`、`Get-TreeObject`、`ConvertTo-TreeJson`：查看和转换目录树
- `Copy-FileSystemItemSafe`、`New-BackupSnapshot`：安全复制和备份
- `Get-ArchiveKind`、`Expand-ArchiveFile`：识别并解压归档文件

### 命令、进程与网络

- `Find-ExecutableCommand`、`Resolve-NativeExecutablePath`：发现原生命令
- `Invoke-NativeCommand`、`Format-NativeCommandLine`：调用和记录原生命令
- `Test-PortOccupation`、`Get-PortProcess`、`Wait-ForURL`：端口与服务检查

### Docker 与 WSL

- `Test-DockerComposeAvailable`、`Invoke-DockerComposeCommand`：Docker Compose 调用
- `Enable-WslDockerWrapper`、`Invoke-WslDocker`：WSL Docker 参数和路径转换
- `Test-DockerDesktopDaemonAvailable`、`Test-WslDockerEngineAvailable`：运行时探测

### 缓存

```powershell
$result = Invoke-WithCache -Key 'system-info' -MaxAge ([TimeSpan]::FromHours(1)) -ScriptBlock {
    Get-ComputerInfo
}

Get-CacheStats
Clear-ExpiredCache -WhatIf
```

`Invoke-WithCache` 支持 `XML` 和 `Text` 两种缓存格式，以及 `-Force`、`-NoCache`
和 `-WhatIf`。缓存目录由模块按当前操作系统选择，不应在调用方硬编码。

### OSS

```powershell
$context = New-OssContext `
    -Bucket 'examplebucket' `
    -Region 'cn-hangzhou' `
    -Host 'static.example.com' `
    -AccessKeyId $env:ALIYUN_ACCESS_KEY_ID `
    -AccessKeySecret $env:ALIYUN_ACCESS_KEY_SECRET

Get-OssObjectList -Context $context -Prefix 'assets/'
```

上传命令包括 `Publish-OssObject` 和 `Publish-OssDirectory`。涉及真实对象存储时，先在
测试 bucket 或受控前缀验证。

### 平台与安装

- `Get-OperatingSystem`、`New-PlatformDescriptor`：平台识别
- `Get-GpuInfo`、`Get-SystemMemoryInfo`：硬件信息
- `Install-RequiredModule`、`Install-ExecutableFile`：依赖安装
- `Install-Font`、`Uninstall-Font`、`New-Shortcut`：平台集成
- `Start-Proxy`、`Close-Proxy`、`Set-Proxy`：当前会话代理管理

## 示例

- [`examples/tree-examples.ps1`](./examples/tree-examples.ps1)：`Get-Tree` 常用参数
- [`examples/help-search-examples.ps1`](./examples/help-search-examples.ps1)：标准帮助和命令发现
- [`examples/test-script-example.ps1`](./examples/test-script-example.ps1)：脚本帮助注释结构
- [`docs/Get-Tree.md`](./docs/Get-Tree.md)：`Get-Tree` 参数与输出说明

活动示例必须使用规范 manifest 或明确的独立子模块入口，并保持无网络下载、无系统配置
修改。历史或具有清理副作用的演示不作为活动入口。

## 测试

在仓库根目录运行：

```powershell
# psutils 包级快速回归
pnpm --filter psutils test:qa

# 根级格式、静态检查与快速测试
pnpm qa

# 主机与 Linux 容器 PowerShell 完整回归
pnpm test:pwsh:all
```

文档和示例契约由 Pester 检查，包括 manifest 事实、弃用入口、脚本语法、导入路径和
安全示例 smoke 执行。

## 版本

- 模块版本：1.0.0
- PowerShell：7.4+ Core
- 作者：mudssky
- 许可：All rights reserved

版本与兼容范围变更时，先更新 `psutils.psd1`，再同步本文档并运行契约测试。
