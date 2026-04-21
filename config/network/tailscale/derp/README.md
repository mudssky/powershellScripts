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
./config/network/tailscale/derp/start.ps1 logs --tail 100
./config/network/tailscale/derp/start.ps1 ps
./config/network/tailscale/derp/start.ps1 pull
./config/network/tailscale/derp/start.ps1 config
./config/network/tailscale/derp/start.ps1 -DryRun
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

- `tailscale netcheck`
- `tailscale ping <另一台设备>`
- `tailscale debug derp`

## 注意事项

- `--verify-clients` 只能限制到 tailnet 级，不能进一步细分“同 tailnet 内哪些设备允许走这个 DERP”
- 如果你把 `derper` 和 `tailscaled-auth` 固定到不同 Tailscale 版本，官方当前不保证 `--verify-clients` 路径稳定可用
- 如果你后续有稳定域名，可以继续沿用这个目录结构，再把 manual cert 路线切换到域名证书方案
