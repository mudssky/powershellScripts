## Apt 包管理器速查表

Apt (Advanced Package Tool) 是 Debian 及其衍生发行版（如 Ubuntu）中用于管理软件包的强大命令行工具。 以下是一份常用 apt 命令的速查表，能帮助您轻松地安装、更新、删除和管理软件包。

### 更新软件包

在安装或升级任何软件包之前，建议先更新本地的软件包索引。

| 命令 | 描述 |
| --- | --- |
| `sudo apt update` | 从配置的源同步软件包信息，更新本地软件包索引。 |
| `sudo apt upgrade` | 将所有已安装的软件包升级到最新版本。 |
| `sudo apt full-upgrade` | 升级软件包，并在必要时删除旧的依赖包以完成整个系统的升级。 |

### 安装软件包

| 命令 | 描述 |
| --- | --- |
| `sudo apt install <软件包名称>` | 安装一个或多个软件包。 |
| `sudo apt install <软件包1> <软件包2>` | 同时安装多个软件包。 |
| `sudo apt install --reinstall <软件包名称>` | 重新安装一个已经安装的软件包。 |
| `sudo apt install -f` | 修复损坏的依赖关系。 |

### 删除软件包

| 命令 | 描述 |
| --- | --- |
| `sudo apt remove <软件包名称>` | 删除指定的软件包，但保留其配置文件。 |
| `sudo apt purge <软件包名称>` | 完全删除指定的软件包及其配置文件。 |
| `sudo apt autoremove` | 自动删除不再被任何已安装软件包使用的依赖包。 |
| `sudo apt clean` | 清除下载的软件包文件（.deb），释放磁盘空间。 |
| `sudo apt autoclean` | 与 `clean` 类似，但只删除那些已经不再可用的旧版本软件包。 |

### 查询软件包

| 命令 | 描述 |
| --- | --- |
| `apt search <关键词>` | 根据关键词搜索软件包。 |
| `apt show <软件包名称>` | 显示特定软件包的详细信息，例如版本、依赖关系等。 |
| `apt list` | 列出所有可用的、已安装的和可升级的软件包。 |
| `apt list --installed` | 只列出已安装的软件包。 |
| `apt list --upgradable` | 列出可以升级的软件包。 |
| `apt depends <软件包名称>` | 显示软件包的依赖关系。 |

### 管理软件源

| 命令 | 描述 |
| --- | --- |
| `sudo add-apt-repository <仓库地址>` | 添加一个新的软件源。 |
| `sudo add-apt-repository --remove <仓库地址>` | 删除一个已有的软件源。 |

**注意:**

* 大多数 `apt` 命令需要管理员权限，因此需要在命令前加上 `sudo`。
* `apt` 是 `apt-get` 和 `apt-cache` 等工具的更新、更用户友好的版本，推荐在日常交互式使用中使用 `apt`。 `apt-get` 仍然适用于脚本编写。
