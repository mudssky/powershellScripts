这份 Cheatsheet 专注于**在被控端（远程机器）开启 SSH 服务**的详细步骤。

只要按照对应的系统操作，开启服务后，你就可以通过 VS Code、终端或任何 SSH 客户端连接。

---

# 🔐 SSH Server 开启全平台速查表 (Cheatsheet)

## 🪟 Windows (10/11)

Windows 10 1809+ 已内置 OpenSSH Server，无需下载第三方软件（如 Putty/Bitvise）。

### 方法 A：设置界面 (最直观)

1. **打开菜单**：`设置` > `系统` (或 `应用`) > `可选功能`。
2. **添加功能**：点击“查看功能”或“添加功能”，搜索 `OpenSSH Server` (OpenSSH 服务器)。
3. **安装**：选中并点击安装，等待完成后重启电脑（可选，但推荐）。
4. **启动服务**：
    * `Win + R` 输入 `services.msc`。
    * 找到 `OpenSSH SSH Server`，双击。
    * 启动类型选 **自动**，点击 **启动**。

### 方法 B：PowerShell (管理员模式 - 最快)

右键开始菜单 -> **终端(管理员)** 或 **PowerShell(管理员)**，依次执行：

```powershell
# 1. 查看是否安装 (如果 State 是 Installed 则跳过第2步)
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

# 2. 安装 OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 3. 启动服务并设置开机自启
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# 4. 检查防火墙规则 (通常自动配置，若无输出需手动添加)
Get-NetFirewallRule -Name *ssh*

# (可选) 手动开放 22 端口防火墙
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

---

## 🐧 Linux (Ubuntu / Debian / CentOS)

大多数服务器版 Linux 默认已安装，如果是桌面版（如 Ubuntu Desktop）通常需要手动安装。

### Ubuntu / Debian / Kali

```bash
# 1. 更新软件源
sudo apt update

# 2. 安装 OpenSSH Server
sudo apt install openssh-server -y

# 3. 启动并设置开机自启
sudo systemctl enable --now ssh

# 4. 检查状态 (应显示 active running)
sudo systemctl status ssh

# 5. 配置防火墙 (如果你开了 ufw)
sudo ufw allow ssh
```

### CentOS / RHEL / Fedora

```bash
# 1. 安装 OpenSSH Server
sudo dnf install openssh-server -y  # 旧版用 yum

# 2. 启动并设置开机自启
sudo systemctl enable --now sshd

# 3. 检查状态
sudo systemctl status sshd

# 4. 配置防火墙 (firewalld)
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload
```

---

## 🍎 macOS

macOS 不需要安装任何东西，只需在系统设置中“打勾”。

### 方法 A：系统设置 (Ventura 13.0+)

1. 打开 **系统设置 (System Settings)**。
2. 进入 **通用 (General)** -> **共享 (Sharing)**。
3. 打开 **远程登录 (Remote Login)** 的开关。
4. 点击右侧 `i` 图标，确保显示“允许所有用户访问”或者指定你的用户名。
    * *注意顶部显示的命令，通常是 `ssh 用户名@IP`，记下它。*

### 方法 B：系统偏好设置 (Monterey 12.0 及更早)

1. 打开 **系统偏好设置** -> **共享**。
2. 左侧勾选 **远程登录**。

### 方法 C：终端命令 (Terminal)

如果你无法接触图形界面，可以使用终端开启：

```bash
# 开启 SSH 服务
sudo systemsetup -setremotelogin on

# 检查 SSH 状态
sudo systemsetup -getremotelogin
```

---

## 🛠️ 通用配置与验证 (Post-Setup)

无论什么系统，开启后的流程是一致的。

### 1. 获取 IP 地址

| 系统 | 命令 |
| :--- | :--- |
| **Windows** | 终端输入 `ipconfig` (看 IPv4 地址) |
| **Linux** | 终端输入 `ip a` 或 `ifconfig` |
| **macOS** | 终端输入 `ifconfig | grep "inet "` |

### 2. 测试连接

在**另一台电脑**的终端输入：

```bash
ssh 用户名@IP地址
# 例如: ssh john@192.168.1.50
```

### 3. 配置文件路径 (进阶修改端口等)

修改配置后需重启服务 (`sudo systemctl restart sshd` 或 `Restart-Service sshd`)。

| 系统 | 路径 | 关键配置项 |
| :--- | :--- | :--- |
| **Linux / Mac** | `/etc/ssh/sshd_config` | `Port 22` (端口)<br>`PasswordAuthentication yes/no` (允许密码登录)<br>`PermitRootLogin yes/no` (允许Root登录) |
| **Windows** | `C:\ProgramData\ssh\sshd_config` | 同上 (注意 ProgramData 是隐藏文件夹) |

---

## 🚨 常见故障排查 (Troubleshooting)

| 现象 | 可能原因 | 解决方案 |
| :--- | :--- | :--- |
| **Connection Refused** | 服务没启动 | 检查 `systemctl status ssh` 或 Windows 服务状态。 |
| **Time out** | 防火墙拦截 / IP错误 | 1. `ping IP地址` 看通不通。<br>2. 检查被控端防火墙是否放行 22 端口。 |
| **Permission denied** | 密码错 / 用户名错 | 1. 确认密码无误。<br>2. Windows 用户如果是微软账号，尝试用 `whoami` 查看真实用户名。 |
| **Windows 公钥无效** | 权限问题 | Windows 的 `authorized_keys` 文件权限极其严格，必须只有 System, Admin 和你自己有权限。 |
