## VSCode (Win11) SSH 连接 macOS 免密登录速查表

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
     > **[提示]** 这是需要复制到 macOS 的文件。

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

### 第 3 步：在 Windows 11 (VSCode)

**1. 打开 SSH 配置文件**

* 通过 "Remote - SSH" 扩展的设置 (⚙️) 图标。
* 选择 `C:\Users\你的用户名\.ssh\config` 文件。

**2. 添加 macOS 主机配置**

* 将以下模板添加到 `config` 文件中，并修改为您自己的信息。

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

**3. 连接**

* 在 VSCode 远程资源管理器中，找到你的主机别名 (`my-mac`) 并点击连接。

---

### 核心要点与故障排查

* **公钥 vs. 私钥**:
  * **公钥 (`.pub`)** -> 放到 **macOS** 服务器上。
  * **私钥 (无后缀)** -> 留在 **Windows** 本地，并在 VSCode `config` 文件中指定路径。
* **macOS 防火墙**: 确保 macOS 的 **系统设置 → 通用 → 共享 → 远程登录** 已开启。
* **网络检查**: 确保 Windows 和 macOS 在同一个局域网内，并且可以互相 `ping` 通。
* **权限问题**: 连接失败最常见的原因是 macOS 上 `~/.ssh` 目录和 `authorized_keys` 文件的权限不正确。请重新执行第 2 步中的 `chmod` 命令。
