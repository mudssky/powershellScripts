## windows 环境配置

1. 安装git
2. 安装powershell
3. 执行 profile/installer/installApp.ps1 安装
4. 执行 profile/profile.ps1 -loadProfile 加载配置

## macos 环境配置

1. 安装git
2. 安装powershell
3. 执行 profile/installer/installApp.ps1 安装
4. 执行 profile/profile_unix.ps1 -loadProfile 加载配置

## linux(wsl) 环境配置

1. 配置wslconfig，执行`./linux/wsl2/loadWslConfig.ps1`
2. 配置wsl2 dns

```
# /etc/wsl.conf 这个文件增加下面的配置后，就不会随机生成了
[network]
generateResolvConf = false
```

之后`sudo vi /etc/resolv.conf`，添加下面的内容

```
nameserver 114.114.114.114
```

3. 安装git,安装gh  `sudo apt install git gh`或者直接执行linux/00
4. 安装homebrew powershell，执行`linux\01installHomeBrew.sh`
5. 执行 `linux\02installApps.ps1`
6. 执行 profile/profile_unix.ps1 -loadProfile 加载配置
