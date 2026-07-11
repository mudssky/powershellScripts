## 前置条件

1. 已安装 `git`
2. 已安装 **PowerShell 7+（`pwsh`）**

> 本项目 Profile 仅支持 `pwsh`，不再支持 Windows PowerShell 5.1。

## Windows 环境配置

1. 从普通用户 Windows PowerShell 执行 `windows/00quickstart.ps1 -Preset Core`
2. 需要 terminal extras 与 AutoHotkey 时使用 `-Preset Full`
3. 使用 `pwsh windows/99verifyInstall.ps1 -Preset Core|Full` 做只读验证

## macOS 环境配置

1. 执行 `zsh macos/00bootstrap.zsh` 完成默认 Core 安装
2. 需要 GUI 与桌面集成时执行 `zsh macos/00bootstrap.zsh --preset Full`
3. 使用 `zsh macos/99verifyInstall.zsh --preset Core|Full` 做只读验证

## Linux（WSL）环境配置

1. 在 Windows 宿主显式执行 `windows/00quickstart.ps1 -IncludeWsl`；配置变化后手工执行 `wsl --shutdown`
2. WSL 客体执行 `linux/00quickstart.sh`，由 `linux/wsl/wsl.conf` 管理 systemd 等客体配置

```text
# /etc/wsl.conf 这个文件增加下面的配置后，就不会随机生成了
[network]
generateResolvConf = false
```

之后执行 `sudo vi /etc/resolv.conf`，添加下面内容：

```text
nameserver 114.114.114.114
```

3. 推荐直接执行 `bash linux/00quickstart.sh --preset Core`
