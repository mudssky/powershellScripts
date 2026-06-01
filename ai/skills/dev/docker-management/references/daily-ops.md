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

这与仓库 `docs/cheatsheet/linux/docker/docker-bind-localhost.md` 的结论一致：宿主机本机仍可访问，同一 Docker 网络内的容器通常仍可通过服务名互联，外部机器不能直接连到该宿主端口。

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

本仓库现役代理入口是 `shell/shared.d/proxy.sh`，适合 WSL2 与原生 Linux 共用。

常用命令：

```bash
proxy on
proxy off
proxy status
proxy docker on
proxy container on
```

- `proxy on` 设置当前 shell 的 `http_proxy` / `https_proxy`。
- `proxy docker on` 写入 Docker daemon systemd drop-in，影响 `docker pull`，会重启 Docker。
- `proxy container on` 写入 `~/.docker/config.json` 的容器代理配置，只影响新建容器。

在 WSL mirrored 网络中，优先使用 `127.0.0.1:<port>` 或显式 `PROXY_DEFAULT_HOST/PORT`，不要再依赖解析 `/etc/resolv.conf` 的旧 NAT 主机 IP 方案。

## 数据卷习惯

- 数据库、对象存储、消息队列等有状态服务优先使用命名卷或清晰的 bind mount 路径。
- 数据目录不要混在源码目录根部；用 `DATA_PATH` 或专门的数据盘目录集中管理。
- compose 配置进 Git，真实 `.env.local` / secret 不进 Git。
- 迁移前用 `docker volume inspect` 和 compose 文件确认每个服务的数据落点。
