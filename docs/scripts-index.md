# PowerShell脚本索引

本文档提供了项目中所有PowerShell脚本的索引和使用说明。

## 目录结构

```text
scripts/
└── pwsh/
    ├── media/          # 媒体处理相关脚本
    ├── filesystem/      # 文件系统操作脚本
    ├── network/         # 网络和下载脚本
    ├── devops/          # DevOps和开发工具脚本
    ├── install/         # Stage 1 安装编排模块
    └── misc/           # 其他杂项脚本

bin/                   # 脚本可执行文件目录
├── run.ps1           # 统一运行入口
└── *.ps1             # 所有脚本的副本
```

## 使用方法

### 1. 直接调用脚本

将 `bin` 目录添加到环境变量PATH后，可以直接在命令行调用任何脚本：

```powershell
# 添加到PATH（临时）
$env:PATH += ";C:\home\env\powershellScripts\bin"

# 调用脚本
VideoToAudio.ps1 -targetPath "C:\Videos\movie.mp4"
renameLegal.ps1 -reverse
```

### 2. 使用统一入口

使用 `bin/run.ps1` 作为统一入口，支持搜索和分类查看：

```powershell
# 列出所有脚本
.\bin\run.ps1 -List

# 按分类查看
.\bin\run.ps1 -Category media

# 搜索脚本
.\bin\run.ps1 -Search video

# 运行脚本
.\bin\run.ps1 VideoToAudio -targetPath "C:\Videos\movie.mp4"
```

### 3. 管理脚本

使用 `Manage-BinScripts.ps1` 管理bin目录的脚本映射：

```powershell
# 同步脚本到bin目录
.\Manage-BinScripts.ps1 -Action sync

# 强制同步（覆盖已存在文件）
.\Manage-BinScripts.ps1 -Action sync -Force

# 清理bin目录
.\Manage-BinScripts.ps1 -Action clean
```

## 脚本分类

### 🎬 Media（媒体处理）

| 脚本名 | 描述 | 关键词 |
|--------|------|--------|
| VideoToAudio.ps1 | 视频转音频脚本，支持多种预设配置和自定义参数 | video, audio, ffmpeg, conversion |
| concatflv.ps1 | FLV文件合并脚本 | flv, merge, concat |
| ffmpegPreset.ps1 | FFmpeg预设配置脚本 | ffmpeg, preset, configuration |
| pngCompress.ps1 | PNG图片压缩脚本 | png, compress, image |
| webpCompress.ps1 | WebP图片压缩脚本 | webp, compress, image |

### 📁 Filesystem（文件系统）

| 脚本名 | 描述 | 关键词 |
|--------|------|--------|
| folderSize.ps1 | 文件夹大小统计脚本 | folder, size, disk, analysis |
| renameLegal.ps1 | 文件名合法化重命名脚本 | rename, legal, filename, windows |
| smallFileCleaner.ps1 | 小文件清理脚本 | clean, small files, disk, maintenance |

### 🌐 Network（网络和下载）

| 脚本名 | 描述 | 关键词 |
|--------|------|--------|
| aliyun-oss-put.ps1 | 阿里云 OSS 上传脚本，支持单文件与目录递归上传，默认不覆盖已有对象 | aliyun, oss, upload, object-storage, cloud |
| downGithub.ps1 | 批量下载指定GitHub用户的所有仓库 | github, download, repository, git |
| downWith.ps1 | 通用下载脚本 | download, http, network |
| startaria2c.ps1 | 启动aria2c下载工具脚本 | aria2c, download, torrent, manager |

### 🔧 DevOps（开发工具）

| 脚本名 | 描述 | 关键词 |
|--------|------|--------|
| Setup-VSCodeSSH.ps1 | 配置VS Code SSH连接的自动化脚本 | vscode, ssh, remote, development |
| Setup-SshNoPasswd.ps1 | SSH免密登录配置脚本 | ssh, passwordless, auth, security |

### 🛠️ Misc（杂项）

| 脚本名 | 描述 | 关键词 |
|--------|------|--------|
| Invoke-PackageSourceBootstrap.ps1 | Windows PowerShell 5.1 的 winget Stage 0 source helper | bootstrap, winget, source, windows |
| Switch-Mirrors.ps1 | 跨平台 package source 计划、事务、状态与恢复入口 | mirror, source, transaction, restore |
| InstallOrchestrator.psm1 | Core/Full 步骤选择、依赖传播、source cleanup 与 Text/JSON 汇总模块 | install, orchestrator, preset, resume |
| ProfileTools.psm1 | Windows/macOS/Linux 共享的 Profile、模块、Node/pnpm、bin 与仓库构建模块 | install, profile, toolchain, cross-platform |
| start-container.ps1 | 容器启动管理脚本 | container, docker, start |
| install.ps1 | 无参数准备仓库工具；显式 Preset 进入跨平台 Stage 1 | install, setup, preset, stage1 |
| syncConfig.ps1 | 配置文件同步脚本 | sync, config, backup |
| proxyHelper.ps1 | 代理助手脚本 | proxy, network, helper |
| cleanEnvPath.ps1 | 环境变量PATH清理脚本 | env, path, clean, environment |
| restoreEnvPath.ps1 | 环境变量PATH恢复脚本 | env, path, restore, environment |
| tesseract.ps1 | Tesseract OCR脚本 | tesseract, ocr, image, text |
| losslessToAdaptiveAudio.ps1 | 无损音频转码脚本（qaac 不存在时回退 libopus） | audio, aac, opus, lossless, qaac, ffmpeg |
| lrc-maker.ps1 | 歌词文件制作脚本 | lrc, lyrics, maker |
| jupyconvert.ps1 | Jupyter转换脚本 | jupyter, convert, notebook |
| gitconfig_personal.ps1 | 个人Git配置脚本 | git, config, personal |
| get-SnippetsBody.ps1 | 获取代码片段内容脚本 | snippets, code, extract |
| findLostNum.ps1 | 查找丢失数字脚本 | find, numbers, missing |
| dvdcompress.ps1 | DVD压缩脚本 | dvd, compress, video |
| dlsiteUpdate.ps1 | DLsite更新脚本 | dlsite, update, download |
| denmodown.ps1 | Denmo下载脚本 | denmo, download |
| concatXML.ps1 | XML文件合并脚本 | xml, concat, merge |
| cleanTorrent.ps1 | 种子清理脚本 | torrent, clean, maintenance |
| cbz.ps1 | CBZ文件处理脚本 | cbz, comic, archive |
| abematv.ps1 | AbemaTV脚本 | abema, tv, video |
| Start-Bee.ps1 | Bee启动脚本 | bee, start |
| ExtractAss.ps1 | 字幕提取脚本 | subtitle, extract, ass |
| DownloadVSCodeExtension.ps1 | VSCode扩展下载脚本 | vscode, extension, download |
| ConventAllbyExt.ps1 | 按扩展名批量转换脚本 | convert, extension, batch |
| pslint.ps1 | PowerShell代码检查脚本 | powershell, lint, code, quality |
| runScripts.ps1 | 脚本运行器 | run, scripts, executor |
| test-lint-staged.ps1 | lint-staged测试脚本 | lint-staged, test, git |

### Linux/WSL 安装流水线

| 入口 | 描述 | 关键词 |
|---|---|---|
| `linux/00quickstart.sh` | Ubuntu/Debian/WSL Stage 0、shallow clone 与 Stage 1 移交 | linux, wsl, bootstrap, stage0 |
| `linux/03configureSources.sh` | 发行版、Linuxbrew 与语言生态 source 事务薄入口 | linux, source, transaction, mirror |
| `linux/05installCoreCli.ps1` | 从统一应用清单安装 Linux Core CLI | linux, homebrew, core, cli |
| `linux/06installFonts.ps1` | Server/WSL 默认跳过、Desktop 显式安装字体 | linux, wsl, fonts, desktop |
| `linux/07installProfileTools.ps1` | Profile、仓库工具、Docker 与 WSL 客体配置 | linux, profile, docker, wsl |
| `linux/08installFullApps.ps1` | Full 预设的 terminal extras，不安装 GUI | linux, full, terminal, cli |
| `linux/99verifyInstall.ps1` | Linux/WSL Core/Full 只读 Text/JSON 验证 | linux, verify, json, status |

### Windows 安装流水线

| 入口 | 描述 | 关键词 |
|---|---|---|
| `windows/00quickstart.ps1` | PS5.1 bootstrap、最小资产校验、一次 UAC 与 Stage 1 移交 | windows, bootstrap, uac, stage0 |
| `windows/01installScoop.ps1` | 普通用户 Scoop 安装与验证 | windows, scoop, package-manager |
| `windows/02installPowerShell.ps1` | winget/MSI PowerShell 7 安装与验证 | windows, powershell, winget, msi |
| `windows/03configureSources.ps1` | winget 只读状态与语言生态 source 事务 | windows, source, mirror, transaction |
| `windows/05installCoreCli.ps1` | 从统一应用清单安装 Windows Core CLI | windows, scoop, core, cli |
| `windows/06installFonts.ps1` | Scoop Nerd Fonts 幂等安装 | windows, fonts, scoop |
| `windows/07installProfileTools.ps1` | Profile、Node/pnpm、bin 与用户 PATH | windows, profile, path, toolchain |
| `windows/08installFullApps.ps1` | Full terminal extras，不安装默认 GUI | windows, full, terminal, cli |
| `windows/09deployAutoHotkey.ps1` | AutoHotkey v2 与当前用户 Startup | windows, autohotkey, startup |
| `windows/99verifyInstall.ps1` | Windows Core/Full 只读 Text/JSON 验证 | windows, verify, json, status |

## 统计信息

- **总脚本数**: 44个
- **分类分布**:
  - Media: 5个
  - Filesystem: 3个
  - Network: 4个
  - DevOps: 2个
  - Misc: 30个

## 最佳实践

### 1. 脚本命名规范

- PowerShell脚本遵循 `Verb-Noun` 格式
- 文件名使用 PascalCase 或 camelCase
- 避免使用特殊字符和空格

### 2. 参数传递

- 所有脚本都支持参数透传
- 使用 `-?` 查看脚本帮助信息
- 参数名称遵循PowerShell约定

### 3. 错误处理

- 脚本包含适当的错误处理
- 使用 `ErrorActionPreference = 'Stop'` 控制错误行为
- 提供有意义的错误消息

### 4. 跨平台兼容

- 脚本支持Windows和Linux环境
- 使用跨平台的路径分隔符
- 避免硬编码绝对路径

## 环境配置

### Windows环境变量设置

1. 打开"系统属性" → "高级" → "环境变量"
2. 在用户变量或系统变量的PATH中添加：

   ```text
   C:\home\env\powershellScripts\bin
   ```

3. 重新打开命令提示符或PowerShell

### PowerShell Profile配置

在PowerShell Profile中添加别名：

```powershell
# 添加到 $PROFILE
Set-Alias -Name run -Value "C:\home\env\powershellScripts\bin\run.ps1"
Set-Alias mg -Value "C:\home\env\powershellScripts\Manage-BinScripts.ps1"
```

## 故障排除

### 常见问题

1. **脚本无法执行**
   - 检查执行策略：`Get-ExecutionPolicy`
   - 设置执行策略：`Set-ExecutionPolicy RemoteSigned`

2. **找不到脚本**
   - 确认bin目录在PATH中
   - 检查脚本名称拼写

3. **参数传递失败**
   - 使用统一入口：`.\bin\run.ps1 ScriptName -param value`
   - 查看脚本帮助：`ScriptName.ps1 -?`

### 获取帮助

```powershell
# 查看统一入口帮助
.\bin\run.ps1 -?

# 查看管理脚本帮助
.\Manage-BinScripts.ps1 -?

# 查看具体脚本帮助
.\bin\VideoToAudio.ps1 -?
```

## 更新日志

- **2025-12-13**: 完成项目重构，建立新的目录结构和bin映射系统
- 支持统一入口和管理脚本
- 完善文档和使用说明
