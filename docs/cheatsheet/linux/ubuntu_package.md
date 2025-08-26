# Ubuntu 包管理器命令 Cheatsheet
安装命令行工具，可以用homebrew，这样就和macos一样了

## APT (Advanced Package Tool)

### 基本命令
- `sudo apt update` - 更新软件包列表
- `sudo apt upgrade` - 升级所有已安装的软件包
- `sudo apt full-upgrade` - 完整系统升级（可能添加/删除软件包）
- `sudo apt install <package_name>` - 安装软件包
- `sudo apt remove <package_name>` - 删除软件包（保留配置文件）
- `sudo apt purge <package_name>` - 完全删除软件包（包括配置文件）
- `sudo apt autoremove` - 删除不再需要的依赖包
- `sudo apt autoclean` - 清理下载的软件包缓存

### 搜索与信息
- `apt search <keyword>` - 搜索软件包
- `apt show <package_name>` - 显示软件包详细信息
- `apt list --installed` - 列出所有已安装的软件包
- `apt list --upgradable` - 列出可升级的软件包
- `apt list --all-versions` - 列出所有版本的软件包

### 修复与维护
- `sudo apt --fix-broken install` - 修复损坏的依赖关系
- `sudo apt check` - 检查依赖关系是否损坏
- `sudo dpkg --configure -a` - 配置所有未配置的软件包

## DPKG (Debian Package)

### 基本命令
- `sudo dpkg -i <package_file.deb>` - 安装.deb文件
- `sudo dpkg -r <package_name>` - 删除软件包（保留配置文件）
- `sudo dpkg -P <package_name>` - 完全删除软件包（包括配置文件）
- `dpkg -l` - 列出所有已安装的软件包
- `dpkg -L <package_name>` - 列出软件包安装的文件
- `dpkg -S <file_path>` - 查找文件属于哪个软件包
- `dpkg -s <package_name>` - 显示软件包状态信息
- `dpkg -c <package_file.deb>` - 列出.deb文件中的内容

### 修复命令
- `sudo dpkg --configure -a` - 配置所有未配置的软件包
- `sudo dpkg --force-all -i <package_file.deb>` - 强制安装软件包

## SNAP (通用软件包管理系统)

### 基本命令
- `sudo snap install <snap_name>` - 安装snap软件包
- `sudo snap remove <snap_name>` - 删除snap软件包
- `snap list` - 列出所有已安装的snap软件包
- `snap find <keyword>` - 搜索snap软件包
- `snap info <snap_name>` - 显示snap软件包信息
- `snap refresh <snap_name>` - 更新snap软件包
- `snap revert <snap_name>` - 恢复到之前的版本
- `snap connections <snap_name>` - 显示snap软件包的连接

## APT-GET (传统APT命令行工具)

### 基本命令
- `sudo apt-get update` - 更新软件包列表
- `sudo apt-get upgrade` - 升级所有已安装的软件包
- `sudo apt-get dist-upgrade` - 系统升级（可能添加/删除软件包）
- `sudo apt-get install <package_name>` - 安装软件包
- `sudo apt-get remove <package_name>` - 删除软件包（保留配置文件）
- `sudo apt-get purge <package_name>` - 完全删除软件包（包括配置文件）
- `sudo apt-get autoremove` - 删除不再需要的依赖包
- `sudo apt-get autoclean` - 清理下载的软件包缓存
- `sudo apt-get clean` - 清理所有下载的软件包缓存

### 源管理
- `sudo apt-add-repository <repository>` - 添加软件源
- `sudo add-apt-repository -r <repository>` - 删除软件源
- `sudo apt-key add <keyfile>` - 添加GPG密钥
- `sudo apt-key del <keyid>` - 删除GPG密钥

## 高级技巧

### 软件源管理
- 编辑 `/etc/apt/sources.list` 文件管理主要软件源
- 编辑 `/etc/apt/sources.list.d/` 目录下的文件管理额外软件源
- `lsb_release -cs` - 获取Ubuntu版本代号（用于配置软件源）

### 下载管理
- `apt-get download <package_name>` - 仅下载软件包不安装
- `apt-get source <package_name>` - 下载软件包源代码
- `apt-get changelog <package_name>` - 查看软件包变更日志

### 锁定软件包版本
- `sudo apt-mark hold <package_name>` - 锁定软件包版本（不更新）
- `sudo apt-mark unhold <package_name>` - 解锁软件包版本
- `apt-mark showhold` - 显示所有锁定的软件包

### 查找依赖关系
- `apt-cache depends <package_name>` - 显示软件包的依赖关系
- `apt-cache rdepends <package_name>` - 显示依赖于该软件包的其他软件包
