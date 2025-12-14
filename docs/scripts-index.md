# PowerShell脚本索引

本文档提供了项目中所有PowerShell脚本的索引和使用说明。

## 目录结构

```
scripts/
└── pwsh/
    ├── media/          # 媒体处理相关脚本
    ├── filesystem/      # 文件系统操作脚本
    ├── network/         # 网络和下载脚本
    ├── devops/          # DevOps和开发工具脚本
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
| Compare-JsonFiles.ps1 | JSON文件对比脚本 | json, compare, diff |
| Switch-Mirrors.ps1 | 镜像源切换脚本 | mirror, switch, network, china |
| start-container.ps1 | 容器启动管理脚本 | container, docker, start |
| install.ps1 | 项目安装脚本 | install, setup, configuration |
| syncConfig.ps1 | 配置文件同步脚本 | sync, config, backup |
| proxyHelper.ps1 | 代理助手脚本 | proxy, network, helper |
| cleanEnvPath.ps1 | 环境变量PATH清理脚本 | env, path, clean, environment |
| restoreEnvPath.ps1 | 环境变量PATH恢复脚本 | env, path, restore, environment |
| tesseract.ps1 | Tesseract OCR脚本 | tesseract, ocr, image, text |
| losslessToQaac.ps1 | 无损音频转AAC脚本 | audio, aac, lossless, qaac |
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

## 统计信息

- **总脚本数**: 43个
- **分类分布**:
  - Media: 5个
  - Filesystem: 3个
  - Network: 3个
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

   ```
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
