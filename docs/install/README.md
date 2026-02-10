## 前置条件

1. 已安装 `git`
2. 已安装 **PowerShell 7+（`pwsh`）**

> 本项目 Profile 仅支持 `pwsh`，不再支持 Windows PowerShell 5.1。

## Windows 环境配置

1. 执行 `profile/installer/installApp.ps1` 安装依赖
2. 执行 `pwsh -File profile/profile.ps1 -LoadProfile` 加载配置

## macOS 环境配置

1. 执行 `profile/installer/installApp.ps1` 安装依赖
2. 执行 `pwsh -File profile/profile.ps1 -LoadProfile` 加载配置

## Linux（WSL）环境配置

1. 配置 `wslconfig`，执行 `./linux/wsl2/loadWslConfig.ps1`
2. 配置 WSL2 DNS

```
# /etc/wsl.conf 这个文件增加下面的配置后，就不会随机生成了
[network]
generateResolvConf = false
```

之后执行 `sudo vi /etc/resolv.conf`，添加下面内容：

```
nameserver 114.114.114.114
```

3. 安装 git 和 gh：`sudo apt install git gh`，或直接执行 `linux/00`
4. 安装 Homebrew 与 PowerShell：执行 `linux\01installHomeBrew.sh`
5. 执行 `linux\02installApps.ps1`
6. 执行 `pwsh -File profile/profile.ps1 -LoadProfile` 加载配置
