# Docker 日常运维

## 目录

- [资源限制](#资源限制)
- [日志轮转](#日志轮转)
- [端口安全绑定](#端口安全绑定)
- [清理与 prune](#清理与-prune)
- [代理](#代理)
- [数据卷习惯](#数据卷习惯)

## 资源限制

容器层优先显式限制关键服务：

```bash
docker run --memory 2g --cpus 2 nginx:latest
```

Compose 中写在服务上：

```yaml
services:
  postgres:
    image: postgres:latest
    mem_limit: 2g
    cpus: 2
```

Windows + WSL2 场景还要在 `%UserProfile%\.wslconfig` 控制 WSL2 VM 总资源。推荐从物理内存的 25%-50%、逻辑核心数的约 50% 起步，再按实际负载调整。

## 日志轮转

Docker 默认 `json-file` 日志可能无限增长。单机开发环境建议在 daemon 层设置默认轮转：

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Linux / WSL2 Docker Engine 常见路径是 `/etc/docker/daemon.json`。修改后重启 Docker：

```bash
sudo systemctl restart docker
```

Compose 中也可以按服务设置：

```yaml
services:
  app:
    image: app:latest
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## 端口安全绑定

本机开发服务默认绑定到 `127.0.0.1`，避免局域网直接访问数据库或管理界面。

```bash
docker run -p 127.0.0.1:5432:5432 postgres:latest
```

Compose 写法：

```yaml
services:
  postgres:
    ports:
      - "127.0.0.1:5432:5432"
```

绑定到 `127.0.0.1` 后，宿主机本机仍可访问，同一 Docker 网络内的容器通常仍可通过服务名互联，外部机器不能直接连到该宿主端口。

## 清理与 prune

清理前先看占用：

```bash
docker system df
docker image ls
docker volume ls
```

低风险清理悬空镜像：

```bash
docker image prune
```

高风险清理未使用资源：

```bash
docker system prune
```

更高风险：清理未使用卷会删除数据卷。只有确认卷没有业务数据或已经备份后再执行：

```bash
docker volume prune
```

## 代理

代理分三层处理：当前 shell、Docker daemon 拉取镜像、新建容器运行环境。不要假设项目内存在代理脚本；直接写入对应层的标准配置。

Windows + WSL2 的 mirrored / NAT 代理地址选择、`host.docker.internal`、`/etc/resolv.conf` 和 `docker pull unexpected EOF` 排查见 `wsl-network-proxy.md`。

当前 shell 临时代理：

```bash
export http_proxy="http://127.0.0.1:7890"
export https_proxy="$http_proxy"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$http_proxy"
export no_proxy="localhost,127.0.0.1,::1"
export NO_PROXY="$no_proxy"
```

关闭当前 shell 代理：

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY
```

Docker daemon 拉取代理，影响 `docker pull`，需要重启 Docker：

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7890"
Environment="HTTPS_PROXY=http://127.0.0.1:7890"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

移除 Docker daemon 代理：

```bash
sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
sudo systemctl daemon-reload
sudo systemctl restart docker
```

新建容器默认代理，写入 `~/.docker/config.json`，只影响之后创建的容器：

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

在 WSL mirrored 网络中，优先使用 `127.0.0.1:<port>` 或 `host.docker.internal:<port>`，不要写死局域网 IP。只有回退到 NAT 模式时，才使用 `/etc/resolv.conf` 的 `nameserver` 地址。

## 数据卷习惯

- 数据库、对象存储、消息队列等有状态服务优先使用命名卷或清晰的 bind mount 路径。
- 数据目录不要混在源码目录根部；用 `DATA_PATH` 或专门的数据盘目录集中管理。
- compose 配置进 Git，真实 `.env.local` / secret 不进 Git。
- 迁移前用 `docker volume inspect` 和 compose 文件确认每个服务的数据落点。
