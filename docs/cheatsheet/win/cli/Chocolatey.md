# Chocolatey 速查

这份 **Chocolatey (Choco) 命令行速查表** 涵盖了从安装、日常使用到高级管理的常用命令。建议在使用前确保以 **管理员身份 (Administrator)** 运行 PowerShell 或 CMD。

---

### 🚀 快速开始 (常用命令)

| 功能 | 命令 | 说明 |
| :--- | :--- | :--- |
| **搜索** | `choco search <关键字>` | 搜索软件包 (同 `choco list`) |
| **安装** | `choco install <包名> -y` | 安装软件并自动确认 |
| **更新单个** | `choco upgrade <包名> -y` | 更新指定软件 |
| **更新所有** | `choco upgrade all -y` | 一键更新所有已安装软件 |
| **卸载** | `choco uninstall <包名>` | 卸载软件 |
| **列出本地** | `choco list --local-only` | 查看已安装的软件列表 |

---

### 📦 安装软件 (Install)

```powershell
# 安装单个包
choco install nodejs

# 自动确认所有提示 (推荐)
choco install git -y

# 安装指定版本
choco install nodejs --version 16.14.0

# 同时安装多个包
choco install googlechrome vscode 7zip -y

# 安装并覆盖参数 (例如安装目录)
choco install notepadplusplus --install-arguments="'/D=C:\Soft\Notepad++'"
```

### 🆙 更新与升级 (Upgrade)

```powershell
# 升级所有已安装的包 (最常用)
choco upgrade all -y

# 升级指定包
choco upgrade python -y

# 强制重新安装 (用于修复损坏的软件)
choco install <包名> --force

# 排除特定包不升级
choco upgrade all --except="chrome,vscode"
```

### 🗑️ 卸载软件 (Uninstall)

```powershell
# 卸载包
choco uninstall 7zip

# 卸载并自动移除未使用的依赖项
choco uninstall nodejs --remove-dependencies
```

### 🔍 查看与搜索 (Search & List)

```powershell
# 搜索包含关键字的包 (默认搜索远程源)
choco search firefox

# 仅通过 ID 精确搜索
choco search firefox --exact

# 查看本地已安装的包
choco list --local-only
# 或者简写
choco list -l

# 查看哪些包需要更新
choco outdated
```

### ℹ️ 信息与详情 (Info)

```powershell
# 查看包的详细信息 (描述、版本、依赖等)
choco info <包名>

# 查看包的安装路径和文件信息 (本地)
choco list <包名> --local-only --verbose
```

### 📌 锁定版本 (Pinning)

*防止特定软件被 `choco upgrade all` 自动更新*

```powershell
# 添加锁定 (禁止更新)
choco pin add -n=<包名>

# 移除锁定 (允许更新)
choco pin remove -n=<包名>

# 列出所有被锁定的包
choco pin list
```

### 🌐 软件源管理 (Sources)

*用于添加私有源或代理*

```powershell
# 列出当前使用的源
choco source list

# 添加新的源
choco source add -n=MySource -s="https://my.nuget.source/v3/index.json"

# 禁用默认的社区源
choco source disable -n=chocolatey
```

---

### ⚙️ 常用参数 (Flags)

大多数命令都支持以下后缀参数：

* `-y` 或 `--yes`: 自动确认所有提示 (Yes to all)。
* `-f` 或 `--force`: 强制执行。
* `--version <版本号>`: 指定特定版本。
* `--pre`: 允许安装预发布版本 (Alpha/Beta)。
* `--params`: 传递特定于包的安装参数。
* `--proxy`: 临时指定代理服务器 (如 `--proxy='http://127.0.0.1:7890'`)。

---

### 🛠️ 安装 Chocolatey (如果尚未安装)

在 **管理员权限** 的 PowerShell 中运行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

### 💡 实用技巧

1. **Tab 补全**: Chocolatey 支持 PowerShell 的 Tab 自动补全，建议安装 `choco-tab-completion` 功能。
2. **清理缓存**: 如果遇到下载错误，尝试清除缓存：`choco cache remove`。
3. **日志位置**: 遇到问题时，查看日志文件：`C:\ProgramData\chocolatey\logs\chocolatey.log`。
