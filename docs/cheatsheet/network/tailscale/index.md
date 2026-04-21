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

---

### 🧩 7. 自建 DERP policy 片段与 tailnet policy 更新

当前官方路线不是在单台机器上执行实验性 CLI 参数，而是：

1. 先把你自己的 DERP 节点跑起来
2. 再把这个节点写进 tailnet policy 的 `derpMap`

仓库内的 `Set-TailscaleDerp.ps1` 负责的是第 2 步：离线编辑 tailnet policy 文件中的
`derpMap`，然后把结果交给你提交到 Tailscale Admin Console 或现有 GitOps 流程。

#### 7.1 先把 DERP 节点跑起来

根据 Tailscale 当前文档，自建 DERP 属于高级操作，你需要自己构建并维护
`cmd/derper`，而不是依赖 `tailscale up` 本地开关。

最短路径：

```bash
go install tailscale.com/cmd/derper@latest
sudo derper --hostname=derp.example.com
```

在这之前，请先满足这些前置条件：

- 给 DERP 服务器准备一个公网域名，并把域名解析到这台机器
- 不要把 `derper` 放在 NAT、全局负载均衡器或普通 HTTP 代理后面
- 防火墙至少放行 `TCP 80`、`TCP 443`、`UDP 3478`
- 允许 ICMP，便于连通性与诊断

如果你启用了 `--verify-clients`，还需要在同机运行 `tailscaled`。如果只是先跑通，
建议先按最小配置启动，再考虑更严格的校验。

#### 7.2 再把节点写进 tailnet policy

`derpMap` 是 tailnet 级网络策略。当前 Tailscale 的 **Visual editor 不能改**
`derpMap`，你必须走：

- Admin Console 的 **JSON editor**
- GitOps 管理的 policy 仓库
- Tailscale API

如果你本地就有 policy 文件，直接用仓库脚本改：

#### 生成并写入受管 Region

```powershell
./scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1 `
  -ServerIp derp.example.com `
  -DerpPort 443 `
  -StunPort 3478 `
  -PolicyPath ./tailnet-policy.hujson
```

如果你不想直接覆盖原始 policy，也可以把结果写到新文件：

```powershell
./scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1 `
  -ServerIp derp.example.com `
  -DerpPort 443 `
  -StunPort 3478 `
  -PolicyPath ./tailnet-policy.hujson `
  -OutputPath ./tailnet-policy.generated.json
```

如果你是在 Admin Console 里直接改 JSON editor，没有本地 policy 文件，先生成片段再粘贴：

```powershell
./scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1 `
  -ServerIp derp.example.com `
  -DerpPort 443 `
  -StunPort 3478 `
  -PrintSnippet
```

脚本默认 `DERPPort` 是 `8443`。如果你是按官方最短命令
`sudo derper --hostname=...` 启动，DERP HTTPS 端口通常就是 `443`，所以要像上面这样
显式传 `-DerpPort 443`，别直接吃脚本默认值。

#### 删除受管 Region

```powershell
./scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1 `
  -Reset `
  -PolicyPath ./tailnet-policy.hujson
```

#### 7.3 生成出来的 `derpMap` 大概长这样

```json
{
  "derpMap": {
    "Regions": {
      "900": {
        "RegionID": 900,
        "RegionCode": "cn-custom",
        "Nodes": [
          {
            "Name": "cn-node",
            "RegionID": 900,
            "HostName": "derp.example.com",
            "DERPPort": 443,
            "STUNPort": 3478,
            "InsecureForTests": true
          }
        ]
      }
    }
  }
}
```

如果你有多台 DERP 机器，第一版建议先做“一个 Region 对应一个 Node”这种最简单模型，
确认跑通后再扩展，不要一上来就做复杂 mesh。

#### 7.4 怎么验证它真的生效了

可以按下面顺序排查：

1. 先看 `tailscale netcheck`
   作用：确认客户端能看到哪些 DERP 候选、UDP 是否正常、NAT 是否困难
2. 再看 `tailscale ping <另一台设备>`
   作用：观察当前连接是直连还是走 DERP 中继
3. 必要时看 `tailscale debug derp`
   作用：进一步看 DERP 侧诊断信息

如果你发现大多数流量长期都在依赖 DERP，中继本身通常不是最优解。Tailscale 官方当前也明确建议：
如果你经常遇到 DERP 中继且性能不够，很多场景下更值得优先考虑 peer relays，而不是长期自维护自定义 DERP。

#### 7.5 这份仓库脚本到底帮你做了什么

- 脚本只管理一个 `RegionID`，默认是 `900`
- 脚本会规范化重写输出文件，不保证保留原 HuJSON 注释与排版
- `-OutputPath` 可把结果写到新文件，避免直接覆盖原始 policy
- `-WhatIf` / `-Confirm` 可用于预览写入动作
- 最后仍需要你把结果提交到 Admin Console 或既有 GitOps 流程

#### 7.6 官方参考

- [DERP servers](https://tailscale.com/docs/reference/derp-servers)
- [Custom DERP servers](https://tailscale.com/docs/reference/derp-servers/custom-derp-servers)
- [Visual policy editor](https://tailscale.com/docs/features/visual-editor)
- [Edit access control policies in your tailnet policy file](https://tailscale.com/docs/features/tailnet-policy-file/manage-tailnet-policies)
