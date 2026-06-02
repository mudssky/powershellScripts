# WSL2 网络与代理

## 目录

- [推荐判断](#推荐判断)
- [网络模式区别](#网络模式区别)
- [Mirrored 模式](#mirrored-模式)
- [NAT 模式](#nat-模式)
- [Docker daemon 代理](#docker-daemon-代理)
- [排查命令](#排查命令)
- [常见结论](#常见结论)

## 推荐判断

优先使用新版 WSL 的 mirrored 网络；不能使用或行为异常时，再回退到 NAT 模式的 Windows 宿主机地址。

| 场景 | 代理地址优先级 | 说明 |
|---|---|---|
| mirrored 网络 | `127.0.0.1:<port>`，其次 `host.docker.internal:<port>` | 不写死局域网 IP；换 Wi-Fi、路由器或 VPN 时更稳 |
| NAT 网络 | `/etc/resolv.conf` 里的 `nameserver:<port>` | 该地址通常是 WSL 访问 Windows 宿主机的网关 |
| Docker daemon 拉取镜像 | 写 systemd drop-in，不只写 shell env | `docker pull` 由 dockerd 发起，不继承普通 shell 的临时代理 |
| 容器内访问外网 | 写 `~/.docker/config.json` 或 compose `environment` | 只影响新建容器，不影响 daemon 拉镜像 |

Windows 代理软件必须真实监听 WSL 可达地址。若只监听 `127.0.0.1`，mirrored 下通常可用；NAT 下通常需要开启 `Allow LAN` / `允许局域网连接`，并确认 Windows 防火墙允许专用网络入站。

## 网络模式区别

`networkingMode` 是 Windows 用户级 `%UserProfile%\.wslconfig` 的 `[wsl2]` 配置项。修改后必须执行 `wsl --shutdown`，再重新进入 WSL 发行版。按 Microsoft Learn 当前说明，WSL2 默认网络模式仍是 `nat`，`mirrored` 需要显式配置。

| 模式 | 默认状态 | 适用判断 | Docker / 代理影响 |
|---|---|---|---|
| `nat` | 默认值 | 兼容性保守；不想改变现有网络行为时使用 | WSL 内 `127.0.0.1` 指向 WSL 自己，不是 Windows。访问 Windows 代理通常要用 `/etc/resolv.conf` 的 `nameserver` 地址，代理软件也常要开启 `Allow LAN`。 |
| `mirrored` | 非默认，需显式设置 | 推荐给 Windows 11 22H2+ 的本机 Docker 开发、VPN、IPv6、localhost 互通场景 | Windows 网络接口会镜像到 WSL，WSL 访问 Windows 本机服务通常可用 `127.0.0.1:<port>`；更适合代理软件、Docker Registry 拉取和 VPN 环境。 |
| `virtioproxy` | 非默认，也可能作为 `nat` 失败时的回退 | 作为 NAT 行为异常时的兼容选项；日常 Docker 开发优先先试 `mirrored` | 依赖 WSL 的 virtio 代理机制，行为比 mirrored 更保守；如果代理或 localhost 互通目标明确，仍要重新验证可达地址。 |
| `none` | 非默认 | 只在需要断网隔离或特殊测试时使用 | WSL 断开网络，Docker 拉取镜像、系统包安装、代理访问都会不可用。 |
| `bridged` | 已弃用 | 不建议新配置 | 老配置里看到时应迁移到 `mirrored` 或回退 `nat`，不要作为新模板推荐。 |

不要把 WSL 的 `networkingMode` 和 Docker Compose 自己的 bridge 网络混在一起：前者决定 WSL 虚拟机怎么连接 Windows 网络，后者决定容器之间和容器到宿主的网络拓扑。排查 Docker 拉镜像优先先确认 WSL 到 Windows 代理是否通，再看 Docker daemon 的 systemd 代理配置。

## Mirrored 模式

确认 WSL 版本和配置：

```powershell
wsl --version
wsl --status
Get-Content "$env:USERPROFILE\.wslconfig"
```

推荐 `.wslconfig` 关键项：

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=true
localhostForwarding=true
```

修改后必须重启 WSL：

```powershell
wsl --shutdown
```

代理测试：

```bash
curl -x http://127.0.0.1:7890 https://registry-1.docker.io/v2/ -I
curl -x http://host.docker.internal:7890 https://registry-1.docker.io/v2/ -I
```

`HTTP/2 401` 或 `401 Unauthorized` 是 Docker Registry 未带 token 时的正常探活结果，说明代理链路能访问 registry。

`autoProxy=true` 依赖 Windows 系统代理配置；代理软件开着但 Windows 系统代理关闭时，WSL 不一定会自动注入 `HTTP_PROXY` / `HTTPS_PROXY`。

## NAT 模式

传统 NAT 模式中，WSL 内的 `127.0.0.1` 是 WSL 自己，不是 Windows。通过 `/etc/resolv.conf` 获取 Windows 宿主机地址：

```bash
WIN_HOST="$(awk '/nameserver/ {print $2; exit}' /etc/resolv.conf)"
echo "$WIN_HOST"
curl -x "http://${WIN_HOST}:7890" https://registry-1.docker.io/v2/ -I
```

NAT 模式通常要求代理软件开启：

```yaml
allow-lan: true
bind-address: "*"
mixed-port: 7890
```

不同代理软件名称不同，重点是代理端口要监听 Windows 的非 loopback 地址，且防火墙允许 WSL 访问。

## Docker daemon 代理

当前 shell 的代理只影响当前进程：

```bash
export http_proxy="http://127.0.0.1:7890"
export https_proxy="$http_proxy"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$http_proxy"
```

Docker daemon 拉取镜像必须写 systemd drop-in：

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7890"
Environment="HTTPS_PROXY=http://127.0.0.1:7890"
Environment="NO_PROXY=localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,.ts.net,100.64.0.0/10"
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

验证 daemon 是否读到代理：

```bash
systemctl show --property=Environment docker
docker info | sed -n '/HTTP Proxy/,+4p'
docker pull hello-world:latest
```

若 mirrored 模式下 `127.0.0.1` 不通但 `host.docker.internal` 通，可以把 drop-in 中的代理地址改成 `http://host.docker.internal:<port>`。不要写死 `192.168.x.x`，除非只是临时排障。

新建容器默认代理写入 Docker CLI 配置：

```bash
mkdir -p ~/.docker
cat >~/.docker/config.json <<'EOF'
{
  "proxies": {
    "default": {
      "httpProxy": "http://127.0.0.1:7890",
      "httpsProxy": "http://127.0.0.1:7890",
      "noProxy": "localhost,127.0.0.1,::1"
    }
  }
}
EOF
```

这只影响之后创建的容器，不会修复 `docker pull`。

## 排查命令

优先使用 skill 自带脚本，避免 PowerShell 与 bash 嵌套引号导致误判：

```powershell
.\scripts\Test-WslDockerProxy.ps1 -Distro Ubuntu -HttpPort 7890
.\scripts\Test-WslDockerProxy.ps1 -Distro Ubuntu -HttpPort 7890 -TestDockerPull
```

脚本默认只诊断，不修改配置。`-TestDockerPull` 会额外执行 `docker pull hello-world:latest` 和 `docker run --rm hello-world`。

Windows 侧检查代理监听地址：

```powershell
Get-NetTCPConnection -LocalPort 7890 -ErrorAction SilentlyContinue |
  Select-Object LocalAddress,LocalPort,State,OwningProcess
```

WSL 侧检查名称解析和端口：

```bash
getent hosts host.docker.internal || true
for hp in 127.0.0.1:7890 host.docker.internal:7890; do
  h="${hp%:*}"
  p="${hp##*:}"
  printf '%s ' "$hp"
  timeout 3 bash -lc "</dev/tcp/$h/$p" >/dev/null 2>&1 && echo ok || echo fail
done
```

区分 shell 代理和 daemon 代理：

```bash
env | grep -i proxy
systemctl show --property=Environment docker
docker info | sed -n '/HTTP Proxy/,+4p'
```

查看 Docker 拉取错误：

```bash
docker --debug pull hello-world:latest
journalctl -u docker --since '10 minutes ago' --no-pager -l
```

## 常见结论

- `curl -x ... https://registry-1.docker.io/v2/` 能返回 401，只说明当前 shell 代理可用；`docker pull` 仍需要 daemon 代理。
- `docker info` 显示了 HTTP Proxy，但仍出现 `unexpected EOF`，通常是代理软件、规则、TLS 中间链路或 Registry 规则问题；继续用 `journalctl -u docker` 和代理客户端日志定位。
- mirrored 模式下可能出现 `localhostForwarding ignored` 提示，这是因为 mirrored 网络已有自己的 localhost 行为，不代表代理一定不可用。
- `external-controller` 不是代理端口，不要把它写进 `HTTP_PROXY`。
- 本机开发默认避免把数据库、Portainer 等服务暴露到局域网；端口绑定优先使用 `127.0.0.1:hostPort:containerPort`。
