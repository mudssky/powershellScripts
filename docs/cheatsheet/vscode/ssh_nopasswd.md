## VSCode (Win11) SSH 连接 Unix 系统免密登录速查表

### 第 1 步：在 Windows 11 (PowerShell / 终端)

**1. 生成 SSH 密钥对**

* 推荐使用 Ed25519 算法。

   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com"
   ```   *   一路按回车键即可 (默认路径，无密码短语)。

**2. 定位密钥文件**

* **私钥 (Private Key):** `C:\Users\你的用户名\.ssh\id_ed25519`
     > **[警告]** 此文件绝对不能泄露！
* **公钥 (Public Key):** `C:\Users\你的用户名\.ssh\id_ed25519.pub`
     > **[提示]** 这是需要复制到目标服务器的文件。

**3. 复制公钥内容**

* 在终端中执行以下命令，然后复制整行输出。

   ```bash
   cat C:\Users\你的用户名\.ssh\id_ed25519.pub
   ```

* 公钥内容以 `ssh-ed25519` 或 `ssh-rsa` 开头。

---

### 第 2 步：在 macOS (终端)

**1. 粘贴公钥**

* 将从 Windows 复制的公钥内容粘贴到 `authorized_keys` 文件中。

   ```bash
   echo "在这里粘贴完整的公钥内容" >> ~/.ssh/authorized_keys
   ```

   > **[注意]** 使用 `>>` 追加，不要用 `>` 覆盖。

**2. 设置正确的文件权限 (非常重要)**

* 如果权限不正确，密钥认证会失败。

   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

---

### 第 2.1 步：在 Linux (终端)

**1. 粘贴公钥**

* 将从 Windows 复制的公钥内容粘贴到 `authorized_keys` 文件中。

   ```bash
   echo "在这里粘贴完整的公钥内容" >> ~/.ssh/authorized_keys
   ```

   > **[注意]** 使用 `>>` 追加，不要用 `>` 覆盖。

**2. 设置正确的文件权限 (非常重要)**

* 如果权限不正确，密钥认证会失败。

   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

**3. 确保 SSH 服务运行**

* **Ubuntu/Debian 系统:**

   ```bash
   # 安装 SSH 服务 (如果未安装)
   sudo apt update
   sudo apt install openssh-server
   
   # 启动并启用 SSH 服务
   sudo systemctl start ssh
   sudo systemctl enable ssh
   
   # 检查服务状态
   sudo systemctl status ssh
   ```

* **CentOS/RHEL/Rocky Linux 系统:**

   ```bash
   # 安装 SSH 服务 (如果未安装)
   sudo yum install openssh-server
   # 或者在较新版本中使用
   sudo dnf install openssh-server
   
   # 启动并启用 SSH 服务
   sudo systemctl start sshd
   sudo systemctl enable sshd
   
   # 检查服务状态
   sudo systemctl status sshd
   ```

* **Arch Linux 系统:**

   ```bash
   # 安装 SSH 服务 (如果未安装)
   sudo pacman -S openssh
   
   # 启动并启用 SSH 服务
   sudo systemctl start sshd
   sudo systemctl enable sshd
   
   # 检查服务状态
   sudo systemctl status sshd
   ```

**4. 配置防火墙 (如果启用)**

* **UFW (Ubuntu):**

   ```bash
   sudo ufw allow ssh
   # 或者指定端口
   sudo ufw allow 22
   ```

* **Firewalld (CentOS/RHEL):**

   ```bash
   sudo firewall-cmd --permanent --add-service=ssh
   sudo firewall-cmd --reload
   ```

---

### 第 3 步：在 Windows 11 (VSCode)

**1. 打开 SSH 配置文件**

* 通过 "Remote - SSH" 扩展的设置 (⚙️) 图标。
* 选择 `C:\Users\你的用户名\.ssh\config` 文件。

**2. 添加目标主机配置**

* 将以下模板添加到 `config` 文件中，并修改为您自己的信息。

   **macOS 主机配置示例:**
   ```
   # 自定义一个易于识别的主机别名
   Host my-mac
       # 替换为 macOS 的 IP 地址或主机名
       HostName 192.168.x.x
       # 替换为 macOS 的登录用户名
       User mac_username
       # 指定 Windows 本地的私钥文件路径 (无 .pub 后缀)
       IdentityFile C:\Users\你的用户名\.ssh\id_ed25519
   ```

   **Linux 主机配置示例:**
   ```
   # 自定义一个易于识别的主机别名
   Host my-linux
       # 替换为 Linux 服务器的 IP 地址或主机名
       HostName 192.168.x.x
       # 替换为 Linux 服务器的登录用户名
       User linux_username
       # 指定 Windows 本地的私钥文件路径 (无 .pub 后缀)
       IdentityFile C:\Users\你的用户名\.ssh\id_ed25519
       # 可选：指定端口 (默认 22)
       Port 22
   ```

**3. 连接**

* 在 VSCode 远程资源管理器中，找到你的主机别名 (如 `my-mac` 或 `my-linux`) 并点击连接。

---

### 核心要点与故障排查

* **公钥 vs. 私钥**:
  * **公钥 (`.pub`)** -> 放到 **目标服务器** (macOS/Linux) 上。
  * **私钥 (无后缀)** -> 留在 **Windows** 本地，并在 VSCode `config` 文件中指定路径。

* **服务器端配置检查**:
  * **macOS**: 确保 **系统设置 → 通用 → 共享 → 远程登录** 已开启。
  * **Linux**: 确保 SSH 服务正在运行 (`sudo systemctl status ssh` 或 `sudo systemctl status sshd`)。

* **网络检查**: 确保 Windows 和目标服务器在同一个局域网内，并且可以互相 `ping` 通。

* **权限问题**: 连接失败最常见的原因是目标服务器上 `~/.ssh` 目录和 `authorized_keys` 文件的权限不正确。请重新执行相应步骤中的 `chmod` 命令。

* **防火墙问题**: 
  * **Linux**: 检查防火墙是否允许 SSH 连接 (端口 22)。
  * **macOS**: 检查系统防火墙设置。

* **SSH 服务配置**:
  * 如果仍无法连接，检查目标服务器的 SSH 配置文件 (`/etc/ssh/sshd_config`)：
    ```bash
    # 确保以下配置项正确
    PubkeyAuthentication yes
    AuthorizedKeysFile .ssh/authorized_keys
    PasswordAuthentication no  # 可选：禁用密码认证
    ```
  * 修改配置后重启 SSH 服务：
    ```bash
    sudo systemctl restart ssh    # Ubuntu/Debian
    sudo systemctl restart sshd   # CentOS/RHEL/Arch
    ```

* **调试连接问题**:
  * 在 Windows 终端中使用详细模式测试连接：
    ```bash
    ssh -v your_username@target_ip
    ```
  * 查看目标服务器的 SSH 日志：
    ```bash
    sudo journalctl -u ssh -f     # Ubuntu/Debian
    sudo journalctl -u sshd -f    # CentOS/RHEL/Arch
    ```
