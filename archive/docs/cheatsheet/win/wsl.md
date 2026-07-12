## WSL2 配置速查表 (Cheatsheet)

这份速查表为你提供了管理和优化 Windows Subsystem for Linux (WSL) 2 所需的关键配置和命令。通过合理配置，你可以更好地控制资源使用、改善网络性能并简化日常工作流程。

### 配置文件概览

WSL2 主要使用两个配置文件，它们用途不同，分工明确：

| 文件名 | `.wslconfig` | `wsl.conf` |
| :--- | :--- | :--- |
| **作用域** | **全局配置**，影响所有 WSL2 发行版。 | **单个发行版配置**，仅影响该文件所在的 Linux 发行版。 |
| **适用版本** | 仅 WSL2。 | WSL1 和 WSL2。 |
| **位置** | Windows 用户目录: `%UserProfile%\.wslconfig` (例如 `C:\Users\YourUser\.wslconfig`) | Linux 发行版内部: `/etc/wsl.conf` |
| **主要用途** | 配置 WSL2 虚拟机 (VM) 的硬件资源，如内存、CPU，以及高级网络功能。 | 配置特定发行版的启动行为、文件系统挂载选项和网络设置等。 |

---

### 全局配置: `.wslconfig`

此文件默认不存在，你需要手动在 `%UserProfile%` 目录下创建它。 每次修改后，都需要在 PowerShell 或 CMD 中运行 `wsl --shutdown` 来关闭所有发行版，然后重新启动它们才能使更改生效。

**文件位置:** `C:\Users\<YourUsername>\.wslconfig`

**常用配置示例:**

```ini
# .wslconfig 示例文件

[wsl2]
# 限制 WSL2 虚拟机最多使用 8GB 内存
memory=8GB 

# 分配 4 个逻辑处理器给 WSL2 虚拟机
processors=4 

# 设置 16GB 的交换空间，0 代表禁用
swap=16GB 

# 将网络模式设置为镜像模式，让 WSL2 和主机共享 IP 地址，简化局域网访问
networkingMode=mirrored

# 允许从 Windows 通过 localhost 访问 WSL2 中绑定的端口
localhostForwarding=true

# (可选) 指定自定义的 Linux 内核路径
# kernel=C:\\path\\to\\my\\kernel
```

**关键配置项说明:**

* `memory=<size>`: 分配给 WSL2 虚拟机的最大内存量 (例如 `8GB`, `1024MB`)。
* `processors=<number>`: 分配给 WSL2 的 CPU 核心数。
* `swap=<size>`: 设置交换空间大小。
* `networkingMode=mirrored`: **(推荐)** 镜像模式，共享主机的网络接口，大大改善网络兼容性和易用性。
* `localhostForwarding=true|false`: 控制是否可以将 WSL2 内部的服务端口转发到主机的 localhost。

---

### 单发行版配置: `wsl.conf`

此文件位于每个 Linux 发行版的 `/etc/` 目录下，用于进行个性化设置。如果文件不存在，你可以使用 `sudo` 权限创建它。修改后同样需要重启对应的发行版才能生效。

**文件位置 (在 WSL 内部):** `/etc/wsl.conf`

**常用配置示例:**

```ini
# /etc/wsl.conf 示例文件

[automount]
# 启用 Windows 驱动器的自动挂载
enabled = true
# 挂载点设置为 /windir/ 而不是默认的 /mnt/
root = /windir/
# 启用文件元数据，允许修改 Windows 文件的权限 (如 chmod, chown)
options = "metadata"

[network]
# 自动生成 /etc/resolv.conf 来管理 DNS
generateResolvConf = true

[user]
# 设置启动发行版时的默认用户
default = your_username

[boot]
# 启动时自动执行命令，例如启动 Docker 服务
# 注意：需要你的发行版支持 systemd
command = service docker start
```

**关键配置项说明:**

* **`[automount]`**:
  * `enabled=true|false`: 控制是否自动挂载 Windows 盘符。
  * `root=<path>`: 自定义 Windows 盘符的挂载根目录。
  * `options="metadata"`: 非常有用，它允许你在 WSL 中正确处理 Windows 文件系统的文件权限。
* **`[network]`**:
  * `generateResolvConf=true|false`: 控制 WSL 是否自动生成 DNS 配置文件。
* **`[user]`**:
  * `default=<username>`: 设置每次打开此发行版时默认登录的用户名。
* **`[boot]`**:
  * `systemd=true|false`: 启用 systemd 支持（需要较新版本的 WSL）。
  * `command="<command>"`: 在发行版启动时执行指定的命令。

---

### 常用命令行管理: `wsl.exe`

这些命令应在 PowerShell 或 CMD 中运行。

| 命令 | 别名 | 描述 |
| :--- | :--- | :--- |
| `wsl --install <Distro>` | | 安装指定的 Linux 发行版。 |
| `wsl --list --online` | | 查看可供安装的发行版列表。 |
| `wsl --list --verbose` | `wsl -l -v` | 列出已安装的发行版及其状态（运行中/已停止）和 WSL 版本。 |
| `wsl --shutdown` | | 立即关闭所有正在运行的发行版和 WSL2 虚拟机。**应用配置更改时常用**。 |
| `wsl --terminate <Distro>` | `wsl -t <Distro>` | 终止指定的发行版。 |
| `wsl --set-version <Distro> <Version>` | | 转换指定发行版的 WSL 版本 (1 或 2)。 |
| `wsl --set-default <Distro>` | `wsl -s <Distro>` | 将指定的发行版设为默认，直接运行 `wsl` 时会启动它。 |
| `wsl --update` | | 更新 WSL 内核版本。 |
| `wsl --export <Distro> <FileName.tar>` | | 将发行版导出为一个 tar 文件作为备份。 |
| `wsl --import <Distro> <InstallLocation> <FileName.tar>` | | 从 tar 文件导入一个发行版，可以自定义安装位置。 |
| `wsl --unregister <Distro>` | | **警告：** 注销并**删除**指定的发行版及其所有数据。 |
| `wsl -u <UserName>` | | 以指定用户身份启动默认发行版。 |
| `wsl hostname -I` | | (在 WSL 内部运行) 查看 WSL 虚拟机的 IP 地址 (NAT 模式下)。 |

### 文件系统交互

* **从 Windows 访问 WSL 文件**:
    在文件资源管理器的地址栏输入 `\\wsl$` 或 `\\wsl.localhost\` 即可访问所有发行版的文件系统。
* **从 WSL 访问 Windows 文件**:
    Windows 的盘符通常挂载在 `/mnt/` 目录下，例如 C 盘对应 `/mnt/c`。
