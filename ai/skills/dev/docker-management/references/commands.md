# Docker 命令速查

## 目录

- [上下文与状态](#上下文与状态)
- [容器](#容器)
- [镜像](#镜像)
- [卷](#卷)
- [网络](#网络)
- [日志与进入容器](#日志与进入容器)
- [Compose 工作流](#compose-工作流)
- [PowerShell 入口验证](#powershell-入口验证)

## 上下文与状态

```bash
docker version
docker info
docker context ls
docker context use default
docker system df
```

Windows 多运行时并存时，先确认 `docker context ls` 指向目标运行时，再启动或清理服务。

## 容器

```bash
docker ps
docker ps -a
docker inspect <container>
docker stop <container>
docker start <container>
docker rm <container>
```

重建容器前先确认数据卷和 bind mount，不要把容器删除误当成数据备份。

## 镜像

```bash
docker images
docker pull postgres:latest
docker build -t my-app:dev .
docker tag my-app:dev registry.example.com/my-app:dev
docker rmi <image>
```

导出/导入本地唯一镜像：

```bash
docker save -o my-app-dev.tar my-app:dev
docker load -i my-app-dev.tar
```

## 卷

```bash
docker volume ls
docker volume inspect <volume>
docker volume create <volume>
docker volume rm <volume>
```

删除卷前先按 `migration-strategy.md` 判断是否需要备份。

## 网络

```bash
docker network ls
docker network inspect <network>
docker network create dev-net
```

同一 compose 项目内优先使用服务名互联，不要通过宿主机暴露端口互相访问。

## 日志与进入容器

```bash
docker logs --tail 200 <container>
docker logs -f <container>
docker exec -it <container> sh
docker exec -it <container> bash
```

容器内没有 `bash` 时用 `sh`。调试后不要把手工改动留在容器内，长期变更应写回 Dockerfile 或 compose。

## Compose 工作流

```bash
docker compose config
docker compose pull
docker compose up -d
docker compose ps
docker compose logs -f --tail 100
docker compose restart <service>
docker compose down
```

指定 profile：

```bash
docker compose --profile db up -d
```

只重建一个服务：

```bash
docker compose up -d --build <service>
```

如果项目已经提供统一启动脚本或 compose wrapper，优先使用项目约定；否则直接使用上面的 `docker compose` 命令。

## PowerShell 入口验证

Docker Desktop 迁到 WSL2-only 后，不要只看 `docker ps` 成功。Windows 项目脚本通常还依赖 compose、相对路径、bind mount 和 `DATA_PATH`。能在 WSL 内直接启动时不需要 wrapper；需要保留 Windows PowerShell 入口时，再按 `wsl-powershell-bridge.md` 在方案 C / D 中选择可选桥接方式。

方案 C 的最小验证：

```powershell
docker version
docker compose version
docker compose -f docker-compose.yml config
```

方案 D 的最小验证：

```powershell
.\scripts\Invoke-WslDocker.ps1 -Distro Ubuntu-24.04 version
.\scripts\Invoke-WslDocker.ps1 -Distro Ubuntu-24.04 compose version

# docker.ps1 shim 或手动 Enable-WslDockerWrapper 生效后：
docker run --rm alpine:3.20 echo ok
docker compose version
```

判断结果：

- `docker version` 失败：Windows CLI 没有连到可用 daemon，先修 context / `DOCKER_HOST`；若采用方案 D，检查 wrapper 是否正确调用 WSL。
- `docker-compose` 失败：Windows 侧缺 compose 插件，项目脚本大概率无法直接启动。
- `compose config` 成功但服务启动失败：能解析 compose，不代表 Windows 路径能被 WSL daemon 挂载；优先处理路径转换或改为 WSL 内运行脚本。
- `data-path` 警告：`${DATA_PATH}` 是 Windows 路径时，迁移后必须用真实服务启动或挂载探针验证。
