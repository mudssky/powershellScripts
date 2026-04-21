# Tailscale DERP Template

这个目录提供仓库内默认的自建 DERP 入口，替代共享 `docker-compose.yml` 里的旧 `derper` 服务。

目录职责：

- `compose.yaml`
  作用：定义 `tailscaled-auth` 与 `derper` 两个服务。
- `Dockerfile.derper`
  作用：构建并运行 `cmd/derper`，避免继续依赖外部第三方 `derper` 镜像。
- `.env.example`
  作用：给出推荐默认值；你通常只需要额外补公网 IP 与 `TS_AUTHKEY`。
- `tailnet-policy.derp.example.hujson`
  作用：提供可直接改 IP 和端口后合并进 tailnet policy 的 `derpMap` 模板。
- `start.ps1`
  作用：统一封装常用 `docker compose` 操作，避免每次手写长命令。

## 设计说明

- `tailscaled-auth` 只负责登录 tailnet、维护 state 和暴露 `tailscaled.sock`
- `derper` 通过 `--verify-clients` + `tailscaled.sock` 把访问范围限制在当前 tailnet
- `derper` 使用 `network_mode: host`
  原因：官方不建议把 DERP 放在 NAT 后面，而 Docker bridge 的 `ports:` 发布本质上就是一层 NAT
- `derper` 使用 `--certmode=manual --certdir=/var/lib/derper/certs`
  当 `DERP_PUBLIC_IP` 是 IP 且 `certdir` 里没有对应 `<IP>.crt/.key` 时，当前 `cmd/derper` 会自动生成自签 IP 证书

## 启动前准备

1. 复制环境变量模板：

```bash
cp config/network/tailscale/derp/.env.example config/network/tailscale/derp/.env.local
```

2. 编辑 `config/network/tailscale/derp/.env.local`

至少填写：

- `DERP_PUBLIC_IP`
- `TS_AUTHKEY`

如果你在当前网络里构建 `Dockerfile.derper` 时访问 `proxy.golang.org` 超时，还建议一起补上：

- `GO_BUILD_IMAGE`
- `ALPINE_MIRROR`
- `GOPROXY`
- `GOSUMDB`

例如：

```dotenv
GO_BUILD_IMAGE=golang:1.26-alpine
ALPINE_MIRROR=https://mirrors.aliyun.com/alpine
GOPROXY=https://goproxy.cn,direct
GOSUMDB=sum.golang.google.cn
```

3. 确认宿主机防火墙已放行：

- `TCP 80`
- `TCP 443`
- `UDP 3478`

## 启动

推荐命令：

```bash
docker compose --env-file config/network/tailscale/derp/.env.local -f config/network/tailscale/derp/compose.yaml --project-directory config/network/tailscale/derp up -d --build
```

如果你习惯 PowerShell，也可以直接用：

```powershell
./config/network/tailscale/derp/start.ps1
```

常用命令：

```bash
docker compose --env-file config/network/tailscale/derp/.env.local -f config/network/tailscale/derp/compose.yaml --project-directory config/network/tailscale/derp logs -f derper
docker compose --env-file config/network/tailscale/derp/.env.local -f config/network/tailscale/derp/compose.yaml --project-directory config/network/tailscale/derp ps
docker compose --env-file config/network/tailscale/derp/.env.local -f config/network/tailscale/derp/compose.yaml --project-directory config/network/tailscale/derp down
```

对应的 `start.ps1` 用法：

```powershell
./config/network/tailscale/derp/start.ps1
./config/network/tailscale/derp/start.ps1 build --no-cache
./config/network/tailscale/derp/start.ps1 logs --tail 100
./config/network/tailscale/derp/start.ps1 ps
./config/network/tailscale/derp/start.ps1 pull
./config/network/tailscale/derp/start.ps1 config
./config/network/tailscale/derp/start.ps1 -DryRun
```

## 构建阶段网络说明

`Dockerfile.derper` 会在构建阶段执行：

```text
go install tailscale.com/cmd/derper@<version>
```

如果你看到类似下面的错误：

```text
Get "https://proxy.golang.org/...": dial tcp ...:443: i/o timeout
```

通常不是 `derper` 本身坏了，而是当前容器网络访问 Go 模块代理超时。此时优先调整：

- `GO_BUILD_IMAGE`
- `ALPINE_MIRROR`
- `GOPROXY`
- `GOSUMDB`

模板已经把这些值透传到 build args，无需再改 Dockerfile。

如果你卡在的是：

```text
RUN apk add --no-cache git
```

通常说明 Alpine 包镜像访问慢或不稳定。此时优先把 `ALPINE_MIRROR` 改成你本地更快的镜像，例如：

```dotenv
ALPINE_MIRROR=https://mirrors.aliyun.com/alpine
```

如果你看到类似下面的错误：

```text
requires go >= 1.26.1 (running go 1.24.x)
```

说明 `derper@latest` 的最低 Go 版本已经高于当前 builder。此时优先把 `GO_BUILD_IMAGE` 提升到
更高版本，例如：

```dotenv
GO_BUILD_IMAGE=golang:1.26-alpine
```

## 证书行为

默认 `DERP_CERTS_DIR=./certs`。第一轮启动时：

- 如果目录里已经有 `${DERP_PUBLIC_IP}.crt` 和 `${DERP_PUBLIC_IP}.key`，`derper` 会直接使用它们
- 如果目录为空，且 `DERP_PUBLIC_IP` 是 IP，`derper` 会自动生成一对自签 IP 证书

这也是当前仓库里 `Set-TailscaleDerp.ps1` 仍然输出 `InsecureForTests = true` 的原因之一：第一版模板默认走
IP-only + 自签证书路线。

## 写入 tailnet policy

容器启动后，再用仓库脚本把同一个公网 IP 写进 tailnet policy：

```powershell
./scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1 `
  -ServerIp 203.0.113.10 `
  -DerpPort 443 `
  -StunPort 3478 `
  -PolicyPath ./tailnet-policy.hujson
```

如果你是直接在 Admin Console 的 JSON editor 里改，可以只生成片段：

```powershell
./scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1 `
  -ServerIp 203.0.113.10 `
  -DerpPort 443 `
  -StunPort 3478 `
  -PrintSnippet
```

如果你更喜欢先改现成模板，再手动合并到 tailnet policy，也可以从这里开始：

`config/network/tailscale/derp/tailnet-policy.derp.example.hujson`

## 验证

模板检查：

```bash
DERP_PUBLIC_IP=203.0.113.10 TS_AUTHKEY=tskey-example docker compose -f config/network/tailscale/derp/compose.yaml --project-directory config/network/tailscale/derp config
```

客户端侧排查：

- `tailscale status`
- `tailscale netcheck`
- `tailscale ping <另一台设备>`
- `tailscale debug derp`

## 排查与常见故障

### 1. 先确认 DERP 容器本身是否正常

```powershell
./config/network/tailscale/derp/start.ps1 ps
./config/network/tailscale/derp/start.ps1 logs --tail 200
```

正常时至少应满足：

- `tailscaled-auth` 与 `derper` 都是 `Up`
- `derper` 日志里没有 `tailscaled.sock`、`verify-clients`、证书加载相关 fatal 错误

### 2. 再确认客户端是否已经收到新的 DERP 配置

```bash
tailscale status
tailscale netcheck
```

重点看：

- 客户端是否在线、目标设备是否在线
- `tailscale netcheck` 里是否能看到你的自定义 DERP region

如果这里完全看不到你的自定义 DERP，优先检查：

- tailnet policy 是否真的保存成功
- `HostName` / `DERPPort` / `STUNPort` 是否和容器配置一致
- 宿主机 `TCP 80`、`TCP 443`、`UDP 3478` 是否放行

### 3. `tailscale ping` 为什么在加了 DERP 配置后反而超时

像下面这种：

```text
tailscale ping macmini
ping "100.x.x.x" timed out
```

最常见不是“DERP 配上了但没被用”，而是“客户端现在需要走中继，但可用中继不可达”。

优先怀疑这几类问题：

1. `OmitDefaultRegions: true`
   影响：你把官方 DERP fallback 关掉了，但自建 DERP 还没完全可用
   建议：在正式验证通过前，先保持 `OmitDefaultRegions: false`
2. `HostName` / `DERP_PUBLIC_IP` / 证书主机名不一致
   影响：客户端看到 DERP 节点，但 TLS 校验或节点匹配失败
3. `InsecureForTests` 缺失或被改掉
   影响：IP-only + 自签证书路线下，客户端不会信任这个 DERP
4. `tailscaled-auth` 在 ACL 中看不到要使用 DERP 的客户端
   影响：`--verify-clients` 会拒绝这些连接
5. 自建 DERP 端口没放行
   影响：客户端无法连上 `443/tcp` 或 `3478/udp`

### 4. 怎么快速判断是不是 DERP 故障

按这个顺序最省时间：

```bash
tailscale status
tailscale netcheck
tailscale ping <另一台设备>
tailscale debug derp
```

辅助看 server 侧：

```powershell
./config/network/tailscale/derp/start.ps1 logs --tail 200
```

经验判断：

- `tailscale ping` 直连成功
  说明当前不需要 DERP，不能说明 DERP 配错
- `tailscale ping` 显示 `via DERP`
  说明当前正在走中继
- `tailscale ping` 持续 timeout
  说明这次连接既没直连成功，也没通过可用 DERP 建立中继

### 5. 关于 `No home relay server`

如果客户端日志或诊断里出现：

```text
No home relay server
```

它通常意味着客户端当前没有可用 DERP 可选。这个场景最值得先查：

- `OmitDefaultRegions` 是否过早设成 `true`
- 自建 DERP 是否真的可达
- policy 是否下发到客户端

### 6. 推荐上线顺序

为了避免“刚加 DERP 就把联通性打断”，推荐顺序是：

1. 先保持 `OmitDefaultRegions: false`
2. 先确认 `tailscale netcheck` 能看到你的自定义 DERP
3. 再观察 `tailscale ping` 是否能在需要时 `via DERP`
4. 最后如果你确实想强制只用自建 DERP，再把 `OmitDefaultRegions` 切到 `true`

### 7. 当前日志里最常见的两类硬故障

如果你看到 `derper` 容器反复重启，并且日志里有：

```text
listen tcp :80: bind: address already in use
```

说明不是 DERP 协议本身坏了，而是宿主机 `80/tcp` 已经被别的服务占用。对当前这套
IP-only + manual cert 模板来说，最简单的处理是：

- 如果你不需要 `80/tcp`，把 `.env.local` 里的 `DERP_HTTP_PORT` 改成 `-1`
- 或者把占用 `80/tcp` 的现有服务停掉

如果你看到 `tailscaled-auth` 日志里有：

```text
invalid key: unable to validate API key
```

说明当前 `TS_AUTHKEY` 无效、过期，或者填错了。这会导致 `tailscaled-auth` 无法成功加入
tailnet，`--verify-clients` 也就失去作用。处理方式是：

- 在 Tailscale Admin 里重新生成一个可用的 auth key
- 更新 `.env.local` 里的 `TS_AUTHKEY`
- 重新执行 `./config/network/tailscale/derp/start.ps1 up`

如果改了 key 之后依旧反复重启，再考虑清理当前 compose 的 state volume 后重启。

## 注意事项

- `--verify-clients` 只能限制到 tailnet 级，不能进一步细分“同 tailnet 内哪些设备允许走这个 DERP”
- 如果你把 `derper` 和 `tailscaled-auth` 固定到不同 Tailscale 版本，官方当前不保证 `--verify-clients` 路径稳定可用
- 如果你后续有稳定域名，可以继续沿用这个目录结构，再把 manual cert 路线切换到域名证书方案
