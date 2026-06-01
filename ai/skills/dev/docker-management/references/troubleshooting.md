# Docker 故障排查

## 目录

- [排查顺序](#排查顺序)
- [Docker daemon 起不来](#docker-daemon-起不来)
- [镜像拉取超时](#镜像拉取超时)
- [端口无法访问或被占用](#端口无法访问或被占用)
- [卷权限问题](#卷权限问题)
- [磁盘占用膨胀](#磁盘占用膨胀)
- [WSL mirrored 网络异常](#wsl-mirrored-网络异常)

## 排查顺序

1. 确认当前运行时：`docker context ls`、`docker info`。
2. 确认 daemon 状态：Linux / WSL2 用 `systemctl status docker`。
3. 确认 compose 配置：`docker compose config`。
4. 确认容器状态和日志：`docker compose ps`、`docker logs`。
5. 再处理网络、代理、权限或磁盘。

## Docker daemon 起不来

症状：`Cannot connect to the Docker daemon`。

定位：

```bash
docker info
systemctl status docker
journalctl -u docker -n 200 --no-pager
```

处置：

- WSL2 内使用 Docker Engine 时，先确认 `/etc/wsl.conf` 有 `[boot] systemd=true`，修改后执行 `wsl --shutdown` 再重开发行版。
- 检查 `/etc/docker/daemon.json` 是否是合法 JSON。
- 配置过代理时，检查 `/etc/systemd/system/docker.service.d/http-proxy.conf`。

## 镜像拉取超时

定位：

```bash
docker pull alpine:latest
proxy status
proxy docker status
systemctl show --property=Environment docker
```

处置：

- 当前 shell 需要代理时执行 `proxy on`。
- Docker daemon 拉取需要代理时执行 `proxy docker on`，该命令会重启 Docker。
- 新建容器内部需要代理时执行 `proxy container on`。
- Windows + WSL2 场景先按 `wsl-network-proxy.md` 区分 mirrored / NAT、shell 代理和 Docker daemon 代理。`curl -x ...` 能通不代表 `docker pull` 已经走代理。

## 端口无法访问或被占用

定位：

```bash
docker ps --format "table {{.Names}}\t{{.Ports}}"
docker compose ps
```

Windows PowerShell：

```powershell
netstat -ano | findstr :5432
```

Linux / WSL2：

```bash
ss -ltnp | grep ':5432'
```

处置：

- 本机访问优先绑定 `127.0.0.1:hostPort:containerPort`。
- 外部访问需要确认 Docker 端口绑定、Windows 防火墙、WSL mirrored Hyper-V 防火墙规则。
- Docker 端口映射不能热修改，通常要重建容器。

## 卷权限问题

症状：容器内报 permission denied，或数据库无法写数据目录。

定位：

```bash
docker inspect <container>
docker volume inspect <volume>
docker exec -it <container> id
```

处置：

- named volume 优先由镜像入口自动初始化权限。
- bind mount 到 Windows 文件系统时，性能和权限语义可能不如 WSL ext4 文件系统；数据库数据建议放在 WSL 发行版内部路径或专用 Linux 文件系统。
- `/etc/wsl.conf` 的 DrvFs `metadata` 可以改善 Windows 挂载盘上的 Linux 权限记录，但不能替代原生 ext4。

## 磁盘占用膨胀

定位：

```bash
docker system df
docker volume ls
du -sh /var/lib/docker 2>/dev/null || true
```

处置：

- 先清理悬空镜像：`docker image prune`。
- 再考虑 `docker system prune`。
- 不确认数据归属时不要执行 `docker volume prune`。
- WSL2 可在 `.wslconfig` 使用 `sparseVhd=true`，并结合 WSL / Windows 的 VHD 压缩流程处理历史膨胀。

## WSL mirrored 网络异常

症状：WSL 内服务本机可访问但局域网不可访问，或 VPN / DNS 行为异常。

定位：

```powershell
wsl --version
wsl --status
```

检查 `%UserProfile%\.wslconfig`：

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
firewall=true
autoProxy=true
```

处置：

- 修改 `.wslconfig` 后必须 `wsl --shutdown`。
- mirrored 模式对入站访问可能需要 Hyper-V 防火墙规则。
- 只做本机开发时，不要为了局域网访问放宽防火墙；优先保持容器端口绑定到 `127.0.0.1`。
- 代理问题优先测试 `127.0.0.1:<port>` 和 `host.docker.internal:<port>`；只有 NAT 模式才使用 `/etc/resolv.conf` 的 `nameserver` 地址。完整流程见 `wsl-network-proxy.md`。
