# 🚀 VS Code 远程开发 Cheatsheet

### 核心决策树

* **都在局域网 / 有公网IP？** $\rightarrow$ 使用 **SSH 直连** (最快、最稳定)
* **跨外网 / 无公网IP / 不想折腾防火墙？** $\rightarrow$ 使用 **Tunnels (隧道)** (最简单)
* **本地 Windows 想用 Linux 环境？** $\rightarrow$ 使用 **WSL 2**
* **需要统一团队环境 / 隔离环境？** $\rightarrow$ 使用 **Dev Containers**

---

## 方案一：SSH 直连 (Standard)

**适用场景：** 局域网开发、有 VPN、服务器有公网 IP。
**特点：** 速度最快，完全控制，行业标准。

| 被控端 (Remote) | 核心准备工作 | 插件名称 |
| :--- | :--- | :--- |
| **Linux** / **macOS** | 安装 SSH 服务 (`sudo apt install openssh-server`) | Remote - SSH |
| **Windows** | 安装 OpenSSH Server (设置 -> 可选功能) | Remote - SSH |

#### 🛠️ 快速配置流程

1. **服务端：** 启动 SSH 服务并放行 22 端口。
2. **客户端：** 安装 **Remote - SSH** 插件。
3. **连接命令：**
    * 点击左下角 `><` 图标 -> `Connect to Host`。
    * 输入：`ssh 用户名@IP地址` (例如 `ssh root@192.168.1.100`)。
4. **免密 (可选但推荐)：**
    * 本地生成：`ssh-keygen`
    * 发送公钥：
        * Linux/Mac: `ssh-copy-id user@host`
        * Windows: 把本地 `id_rsa.pub` 内容复制到远程 `~/.ssh/authorized_keys`。

---

## 方案二：Tunnels 隧道 (Easy Access)

**适用场景：** 家里连公司电脑、咖啡厅连家里电脑、**没有公网 IP**。
**特点：** 微软官方内网穿透，无需配置路由器/防火墙，只需登录 GitHub 账号。

| 被控端 (Remote) | 核心准备工作 | 插件名称 |
| :--- | :--- | :--- |
| **Win / Mac / Linux** | 下载 VS Code CLI 或安装 VS Code 桌面版 | Remote - Tunnels |

#### 🛠️ 快速配置流程

1. **服务端 (被控端)：**
    * **方法 A (有界面)：** 打开 VS Code -> 左下角头像 -> `Turn on Remote Tunnel Access` -> 登录 GitHub。
    * **方法 B (无界面/服务器)：** 下载 `code` CLI 工具，运行 `./code tunnel` -> 根据提示登录 GitHub。
2. **客户端 (主控端)：**
    * 安装 **Remote - Tunnels** 插件。
    * 点击左下角 `><` -> `Connect to Tunnel`。
    * 登录同一个 GitHub 账号，即可看到远程机器列表。

---

## 方案三：本地虚拟化 (Local Virtualization)

**适用场景：** 在 Windows 上需要 Linux 工具链，或者不想污染本机环境。

| 场景 | 被控端环境 | 插件名称 |
| :--- | :--- | :--- |
| **Windows 用 Linux** | **WSL 2** (Ubuntu/Debian 等子系统) | WSL |
| **环境隔离 / 团队协作** | **Docker** 容器 | Dev Containers |

#### 🛠️ 快速配置流程

* **WSL：** Windows 终端输入 `code .` 即可直接在该目录下启动 VS Code 并连接到 WSL。
* **Dev Containers：** 项目根目录包含 `.devcontainer` 文件夹 -> 打开项目 -> VS Code 提示 "Reopen in Container"。

---

## ⚡ 常用命令速查表 (Cheat Table)

| 动作 | 命令 / 快捷键 | 备注 |
| :--- | :--- | :--- |
| **打开远程菜单** | `F1` 或 `Ctrl+Shift+P` -> 输入 `Remote` | 所有远程功能的入口 |
| **查看 SSH 配置文件** | `~/.ssh/config` (Mac/Linux)<br>`C:\Users\用户\.ssh\config` (Win) | 可以在这里配置别名、端口、私钥路径 |
| **杀掉远程 VSCode 服务** | 远程终端运行 `rm -rf ~/.vscode-server` | 遇到连接莫名卡死、报错时的终极修复法 |
| **查看连接日志** | 面板 -> `输出` (Output) -> 选择 `Remote - SSH` | 排查连接失败原因 |

---

## 💻 跨系统连接矩阵 (Matrix)

| 本地 (Local) | 远程 (Remote) | 推荐方案 | 关键点 |
| :--- | :--- | :--- | :--- |
| **Windows** | **Windows** | **SSH** (局域网) / **Tunnels** (外网) | 远程需开启 OpenSSH Server |
| **Windows** | **Linux** | **SSH** (远程) / **WSL** (本地) | 最常见的开发组合 |
| **Mac** | **Linux** | **SSH** | 原生支持，体验极佳 |
| **Mac** | **Windows** | **SSH** | 远程 Windows 需设为 Powershell 默认终端 |
| **iPad/浏览器** | **Any** | **Tunnels** | 访问 `vscode.dev` 并连接 Tunnel |

### ⭐ 最佳实践建议

1. **长期开发：** 只要两台电脑能 ping 通，首选 **SSH**，稳定性最高。
2. **临时/移动办公：** 首选 **Remote Tunnels**，不用管 IP 变动，随开随用。
3. **Windows 用户：** 强烈建议学习 **WSL 2**，它能让你在 Windows 上拥有原生的 Linux 开发体验，且与 VS Code 集成完美。
