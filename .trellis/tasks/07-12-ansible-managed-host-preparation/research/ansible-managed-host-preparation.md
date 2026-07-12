# Ansible 三平台被控端准备操作

## 1. 通用原则

- 准备脚本在被控端本机运行，不在目标机安装 Ansible。
- 默认 Preview；确认结果后显式 Apply。
- 能自动安装的前置会自动安装：Tailscale、SSH server、Python 3、sudo/提权依赖和服务。
- 账号登录、设备批准、macOS 系统权限、重启或重新登录等强制交互会出现在 `ManualSteps`。
- 完成人工步骤后执行结果中的 `RerunCommand`，直到状态为 `Succeeded`。
- 脚本不写 SSH 私钥，不覆盖 `sshd_config` 或认证策略，不改变防火墙全局开关。

## 2. Windows 单文件准备

目标机：

```text
HostName: iminipro820
UserName: mudssky
TailscaleIPv4: 100.125.34.90
```

在 `iminipro820` 打开 Windows PowerShell。若没有完整仓库，可只下载入口文件：

```powershell
$scriptPath = Join-Path $env:TEMP 'Prepare-WindowsAnsibleHost.ps1'
Invoke-WebRequest `
    -Uri 'https://raw.githubusercontent.com/mudssky/powershellScripts/master/windows/bootstrap/Prepare-WindowsAnsibleHost.ps1' `
    -UseBasicParsing `
    -OutFile $scriptPath
```

入口会在需要时从同一个 GitHub revision 下载依赖模块到临时目录。正式固定版本时可把 `master` 和 `-SourceRevision master` 替换为具体 commit。

普通 PowerShell 先 Preview：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $scriptPath `
    -TailscaleIPv4 100.125.34.90 `
    -OutputFormat Text
```

右键 Windows Terminal 或 Windows PowerShell，选择“以管理员身份运行”，再 Apply：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $scriptPath `
    -TailscaleIPv4 100.125.34.90 `
    -Apply `
    -OutputFormat Text
```

脚本会自动完成：

1. 缺失时用 winget 安装 Tailscale。
2. 安装 `OpenSSH.Server~~~~0.0.1.0` Windows capability。
3. 将 `sshd` 设置为 Automatic 并启动。
4. 将 OpenSSH DefaultShell 设置为 Windows PowerShell 5.1。
5. Windows Firewall 开启时增加 Tailscale scoped TCP 22 rule；防火墙关闭时保持关闭。
6. 验证 TCP 22 listener，但不声称其只监听 Tailscale；OpenSSH 默认仍可能监听 LAN 接口。

若 Tailscale 尚未登录：

1. 打开系统托盘或开始菜单中的 Tailscale。
2. 选择 `Log in`。
3. 在浏览器完成账号授权和设备批准。
4. 回到管理员 PowerShell 验证：

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' ip -4
```

若 capability 要求重启：

```powershell
Restart-Computer
```

重启后重新运行原 Apply 命令。

Windows 本机验证：

```powershell
Get-WindowsCapability -Online -Name OpenSSH.Server*
Get-Service sshd
Get-CimInstance Win32_Service -Filter "Name='sshd'" | Select-Object Name, State, StartMode
Get-ItemProperty HKLM:\SOFTWARE\OpenSSH -Name DefaultShell
Get-NetTCPConnection -State Listen -LocalPort 22
```

从任一 tailnet 控制端验证：

```bash
ssh mudssky@100.125.34.90
```

SSH 成功后，在 Windows 管理员 SSH 会话内 Preview PSRP bootstrap：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File .\windows\bootstrap\Enable-WindowsRemotePsRemoting.ps1 `
    -TailscaleIPv4 100.125.34.90 `
    -WhatIf
```

确认后去掉 `-WhatIf`。随后 Ansible control plane 切换到 PSRP HTTPS `5986`。

## 3. Linux 准备

支持 Ubuntu/Debian 与 Arch，目标机本地执行：

```bash
cd powershellScripts
bash linux/bootstrap/prepare-ansible-host.sh --output-format text
bash linux/bootstrap/prepare-ansible-host.sh --apply --output-format text
```

脚本会自动安装并启用：

- Ubuntu/Debian：`openssh-server python3 sudo curl`。
- Arch：`openssh python sudo curl`。
- Tailscale 官方安装脚本和 `tailscaled` systemd service。
- `ssh` 或 `sshd` systemd service。
- 活动 ufw/firewalld 下的 tailnet TCP 22 rule，不改变全局开关。

安装后未登录 tailnet 时，在目标机运行：

```bash
sudo tailscale up
```

打开命令输出的浏览器地址完成授权，然后验证：

```bash
tailscale ip -4
python3 --version
systemctl is-enabled ssh 2>/dev/null || systemctl is-enabled sshd
systemctl is-active ssh 2>/dev/null || systemctl is-active sshd
ss -lnt | grep ':22 '
```

最后重跑 Apply。WSL 默认不建立独立 SSH 管理面；优先由 Ansible 管理 Windows 宿主。

## 4. macOS 准备

目标机本地执行：

```zsh
cd powershellScripts
zsh macos/bootstrap/prepare-ansible-host.zsh --output-format text
zsh macos/bootstrap/prepare-ansible-host.zsh --apply --output-format text
```

脚本会自动：

1. 缺失时复用 `macos/01installHomebrew.zsh` 安装 Homebrew。
2. 用 Homebrew 安装 Python 3。
3. 用 Homebrew cask 安装并打开 Tailscale App。
4. 用 `systemsetup` 启用 Remote Login。
5. Application Firewall 开启时允许系统 SSH wrapper，但不改变全局开关。

若 macOS 要求批准 Tailscale 网络扩展：

1. 打开“系统设置 > 通用 > 登录项与扩展 > 网络扩展”。
2. 允许 Tailscale 网络扩展。
3. 打开 Tailscale App，选择 `Log in` 并在浏览器授权。
4. 等待 App 显示 Connected。

若 `systemsetup` 报权限不足：

1. 打开“系统设置 > 隐私与安全性 > 完全磁盘访问权限”。
2. 为当前 Terminal、iTerm2 或 VS Code 授权。
3. 完全退出并重新打开终端。
4. 执行：

```zsh
sudo systemsetup -setremotelogin on
```

验证：

```zsh
sudo systemsetup -getremotelogin
python3 --version
/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4
sudo lsof -nP -iTCP:22 -sTCP:LISTEN
```

完成人工步骤后，重新执行 Apply 命令。

## 5. 控制端连接

Linux/macOS 控制端原生运行 Ansible；Windows 控制端在 WSL2 Ubuntu 中运行。通过 VS Code Remote SSH 登录 Linux 控制端时，命令完全相同。

初始化 control plane：

```bash
git clone <self-hosted-compose-private-url>
cd self-hosted-compose
git submodule update --init --recursive
cd deployments/ansible
```

先做连接检查和 WhatIf，真实 apply 始终显式指定单台主机 `--limit`。inventory、secrets 路径和 playbook 命令以 `self-hosted-compose/deployments/ansible` 的包装入口为准。
