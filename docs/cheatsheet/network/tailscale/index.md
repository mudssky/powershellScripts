这是一份专为**拥有云服务器（Linux）的用户**定制的 Tailscale 速查表（Cheatsheet）。涵盖了从基础安装到进阶的“路由转发”、“出口节点”等常用命令。

建议收藏，配合你的云服务器使用。

---

### 🚀 1. 安装与基础启停

| 场景 | 命令 / 操作 | 备注 |
| :--- | :--- | :--- |
| **一键安装** (Linux) | `curl -fsSL <https://tailscale.com/install.sh> | sh` | 官方脚本，自动适配发行版 |
| **启动/登录** | `sudo tailscale up` | 会打印出一个 URL，复制到浏览器登录 |
| **停止服务** | `sudo tailscale down` | 断开连接，释放网络资源 |
| **完全注销** | `sudo tailscale logout` | 登出账号，下次需重新认证 |
| **开机自启** | `sudo systemctl enable --now tailscaled` | 确保服务器重启后自动连上 |

---

### 🔍 2. 状态检查与排查 (Debug)

**这是你最常用的部分，用于判断“直连”还是“中继”。**

| 场景 | 命令 | 输出解读 |
| :--- | :--- | :--- |
| **查看节点列表** | `tailscale status` | 列出所有设备 IP、系统、在线状态 |
| **查看本机 IP** | `tailscale ip -4` | 获取本机的 100.x.x.x 内网 IP |
| **测试连通性** (关键) | `tailscale ping <目标IP或主机名>` | **via IP:Port** = P2P直连 (快)<br>**via DERP** = 走中继 (慢) |
| **检查网络环境** | `tailscale netcheck` | **UDP: true** = 正常<br>**MappingVariesByDestIP: true** = 困难NAT (难直连) |
| **实时流量监控** | `tailscale nc` | 类似 netcat，用于高级调试 |

---

### 🛡️ 3. 进阶功能：云服务器专用

利用你的 VPS 作为网关或代理。

#### A. 开启 Exit Node (作为梯子/全局代理)

*让手机/电脑的流量全部经过这台云服务器转发。*

1. **开启 IP 转发 (Linux 系统层)**:

    ```bash
    echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
    echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
    sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
    ```

2. **启动广播**:

    ```bash
    sudo tailscale up --advertise-exit-node
    ```

3. **最后一步**: 去 [Tailscale 管理面板](https://login.tailscale.com/admin/machines) > 点击该机器 > **Edit route settings** > 勾选 **Use as exit node**。

#### B. 开启 Subnet Router (内网穿透)

*让你在家直接访问云服务器所在 VPC 里的其他内网服务 (如 RDS 数据库)。*

1. **启动广播 (假设内网段是 192.168.0.0/24)**:

    ```bash
    sudo tailscale up --advertise-routes=192.168.0.0/24
    ```

2. **最后一步**: 去管理面板 > **Edit route settings** > 批准该路由。

#### C. 开启 Tailscale SSH (丢掉 Key 密钥)

*通过 Tailscale 认证直接 SSH，无需管理 authorized_keys。*

```bash
sudo tailscale up --ssh
```

* **连接方式**: 在客户端 `ssh <用户名>@<服务器TailscaleIP>` 或 `ssh <用户名>@<MagicDNS域名>`

---

### 📂 4. 文件传输 (Taildrop)

类似 AirDrop 的局域网传文件功能。

| 场景 | 命令 | 备注 |
| :--- | :--- | :--- |
| **发送文件** | `tailscale file cp <文件名> <目标机器名>:` | 注意最后有个冒号 `:` |
| **接收文件** (Linux) | `tailscale file get <目标目录>` | 默认接收路径通常在 `/var/lib/tailscale/` |
| **查看收件箱** | `tailscale file list` | 查看有哪些文件待接收 |

---

### ⚙️ 5. 高级配置与优化

当遇到网络问题时使用。

| 参数 | 完整命令示例 | 作用 |
| :--- | :--- | :--- |
| **修改主机名** | `tailscale set --hostname=my-vps` | 在管理面板显示的名字，方便记忆 |
| **指定固定端口** | (需修改 `/etc/default/tailscaled` 配置文件) | 配合防火墙放行 UDP 41641 以提升直连率 |
| **调整 MTU** | `tailscale up --mtu=1200` | 解决部分网络下握手成功但传输卡死的问题 |
| **不接受路由** | `tailscale up --accept-routes=false` | 仅本机加入网络，不接受其他节点广播的子网路由 |
| **自动更新** | `tailscale set --auto-update` | 让客户端自动保持最新 (推荐) |

---

### 💡 6. 组合技示例 (最强形态)

如果你想把云服务器配置成：**既是 SSH 服务器，又是出口节点 (Exit Node)，还是内网路由 (Subnet Router)，并且自定义了主机名**。

请运行这条“终极命令”：

```bash
sudo tailscale up \
  --advertise-exit-node \
  --advertise-routes=10.0.0.0/24 \
  --ssh \
  --hostname=aliyun-shanghai
```

*(注意：运行后别忘了去网页控制台勾选批准 Route 和 Exit Node)*

### 📝 附：常用端口与防火墙设置

为了保证**高直连率**，请务必在云服务器的安全组/防火墙中放行：

* **协议**: UDP
* **端口**: `41641` (这是 Tailscale 默认首选端口，放行它能大幅减少掉线和延迟)
* **方向**: 入站 (Inbound) 和 出站 (Outbound)
