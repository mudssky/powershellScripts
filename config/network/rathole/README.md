# rathole template

这个目录提供 rathole 裸二进制 + PM2 的配置示例和维护脚本。它适合把内网服务暴露到一台公网入口服务器，也适合“目标服务只允许某台公网 IP 访问”的白名单转发场景。

目录职责：

- `server.example.toml`
  作用：rathole server 示例，复制为 `server.local.toml` 后在公网入口机器运行。
- `client.example.toml`
  作用：rathole client 示例，复制为 `client.local.toml` 后在内网服务所在机器运行。
- `whitelist-proxy.example.toml`
  作用：公网白名单转发示例，复制为 `client.local.toml` 后在白名单公网服务器运行。
- `rathole-server.pm2.config.cjs`
  作用：PM2 server 进程配置。
- `rathole-client.pm2.config.cjs`
  作用：PM2 client 进程配置。
- `start.ps1`
  作用：统一封装常用 PM2 操作，避免每次手写长命令。

## 设计说明

- rathole 本身是单二进制，常驻资源占用比容器方案更直接。
- PM2 负责后台运行、日志、重启和开机恢复；rathole 负责 TCP/UDP 四层转发。
- server/client 的 PM2 配置拆成两个文件，避免一台机器误启动不需要的一端。
- 真实配置统一使用 `.local.toml`，其中可能包含 token、内网地址和白名单目标地址，默认不会提交到 Git。

## 准备 rathole 和 PM2

先确认机器上可以直接运行 rathole：

```bash
rathole --version
```

如果 rathole 不在 `PATH`，可以通过环境变量指定二进制路径：

```bash
RATHOLE_BIN=/opt/rathole/rathole pm2 start config/network/rathole/rathole-client.pm2.config.cjs
```

安装 PM2：

```bash
npm install -g pm2
```

## 基础 server/client 转发

1. 在公网入口机器复制 server 配置：

```powershell
Copy-Item `
  -LiteralPath config/network/rathole/server.example.toml `
  -Destination config/network/rathole/server.local.toml
```

编辑 `server.local.toml`：

- `server.bind_addr`：rathole client 连接入口，例如 `0.0.0.0:2333`
- `server.services.<name>.token`：每个服务独立 token
- `server.services.<name>.bind_addr`：对外暴露端口，例如 `0.0.0.0:5202`

2. 在内网服务所在机器复制 client 配置：

```powershell
Copy-Item `
  -LiteralPath config/network/rathole/client.example.toml `
  -Destination config/network/rathole/client.local.toml
```

编辑 `client.local.toml`：

- `client.remote_addr`：公网入口机器地址，例如 `rathole.example.com:2333`
- `client.services.<name>.token`：必须与 server 端同名服务一致
- `client.services.<name>.local_addr`：本机或内网服务地址，例如 `127.0.0.1:22`

3. 启动：

```powershell
# 公网入口机器
./config/network/rathole/start.ps1 start -Role server

# 内网服务机器
./config/network/rathole/start.ps1 start -Role client
```

## 公网白名单转发

如果某个第三方服务只允许固定公网 IP 访问，可以把 rathole client 部署在那台已加入白名单的公网服务器上：

```powershell
Copy-Item `
  -LiteralPath config/network/rathole/whitelist-proxy.example.toml `
  -Destination config/network/rathole/client.local.toml
```

编辑 `client.local.toml`：

- `client.remote_addr`：rathole 入口 server 地址
- `client.services.<name>.local_addr`：白名单目标服务地址，例如 `api.allowlist-only.example.com:443`
- `client.services.<name>.token`：与入口 server 同名服务一致

访问链路：

```text
调用方 -> rathole server 暴露端口 -> rathole 隧道 -> 白名单公网服务器上的 rathole client -> 白名单目标服务
```

目标服务看到的来源 IP 是白名单公网服务器。

### HTTP/HTTPS 转发边界

你的白名单场景本质上是“让请求从某台已加入白名单的公网服务器发出去”。如果这台白名单服务器本身就是你对外暴露入口的机器，并且它能直接访问目标 HTTP/HTTPS 服务，优先用 Nginx/Caddy 这类 HTTP 反向代理会更直观：

```nginx
server {
    listen 8443 ssl;
    server_name proxy.example.com;

    location / {
        proxy_pass https://api.allowlist-only.example.com;
        proxy_set_header Host api.allowlist-only.example.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

这种情况下，目标服务看到的来源 IP 就是这台 Nginx 所在白名单服务器的公网 IP，而且你还能顺手处理域名、路径、Header、证书等 HTTP 细节。

rathole 适合下面这种更像“隧道”的情况：

- 入口端口不在白名单服务器上，需要把入口流量穿到白名单服务器再出去。
- 目标不是 HTTP，或者你只想原样透传 TCP/UDP。
- 白名单服务器不想跑完整 HTTP 反代配置，只需要固定端口转固定目标。

只要目标是一个固定 HTTP/HTTPS 服务，并且你只需要把一个入口端口转到一个目标地址，rathole 直接透传 TCP 也够用。例如：

```toml
[client.services.whitelist_api]
token = "replace-with-a-long-random-token"
local_addr = "api.allowlist-only.example.com:443"
```

对应 server 端暴露一个入口端口：

```toml
[server.services.whitelist_api]
token = "replace-with-a-long-random-token"
bind_addr = "0.0.0.0:8443"
```

访问 `公网入口:8443` 时，流量会原样进入白名单公网服务器，再由这台服务器访问 `api.allowlist-only.example.com:443`。如果这是 HTTPS，TLS 握手和证书校验发生在调用方与最终 HTTPS 服务之间，rathole 不解密也不改包。

这句话“rathole 不处理 HTTP Host、路径、Header 或 TLS 终止”的实际含义是：

- 能做：`公网入口:8443 -> api.allowlist-only.example.com:443`
- 能做：`公网入口:8080 -> 127.0.0.1:3000`
- 不能单独做：同一个入口端口按 `a.example.com` / `b.example.com` 分流到不同服务
- 不能单独做：同一个入口端口按 `/api` / `/static` 分流
- 不能单独做：替你添加 `X-Forwarded-For`、重写 `Host` 或统一签发/终止 HTTPS 证书

如果你只是借白名单服务器的公网 IP 访问某个固定 HTTP/HTTPS 服务，rathole 足够。如果你要“一个 443 端口承载多个域名、多个路径、统一证书”，就把 Nginx、Caddy 或 Traefik 放在 rathole 的一端或两端，让它们负责七层 HTTP 逻辑。

## PM2 管理

默认管理 client：

```powershell
./config/network/rathole/start.ps1
```

常用命令：

```powershell
./config/network/rathole/start.ps1 start -Role client
./config/network/rathole/start.ps1 start -Role server
./config/network/rathole/start.ps1 logs --lines 100
./config/network/rathole/start.ps1 status
./config/network/rathole/start.ps1 restart -Role client
./config/network/rathole/start.ps1 stop -Role client
./config/network/rathole/start.ps1 delete -Role client
./config/network/rathole/start.ps1 save
./config/network/rathole/start.ps1 config -Role client
./config/network/rathole/start.ps1 -DryRun
```

保存当前 PM2 进程列表：

```bash
pm2 save
```

配置开机恢复：

```bash
pm2 startup
pm2 save
```

## 裸二进制直接运行

不需要 PM2 时可以直接运行：

```bash
rathole config/network/rathole/server.local.toml
rathole config/network/rathole/client.local.toml
```

也可以显式指定模式：

```bash
rathole --server config/network/rathole/server.local.toml
rathole --client config/network/rathole/client.local.toml
```

## Docker Compose 备选

如果后续你更想用容器，可以把同样的 `.local.toml` 挂载进 rathole 镜像。但本目录第一版不提供 Compose 生命周期脚本，因为当前主线是低资源占用的裸二进制 + PM2。

## 排查

查看 PM2 状态和日志：

```powershell
./config/network/rathole/start.ps1 status -Role client
./config/network/rathole/start.ps1 logs -Role client --lines 200
```

确认端口监听：

```bash
ss -lntup | grep -E '2333|5202|8080'
```

确认 token 与服务名：

- server/client 两端的 service 名必须一致
- 同名 service 的 token 必须一致
- server 的 `bind_addr` 是暴露给调用方的端口
- client 的 `local_addr` 是最终要访问的服务地址
