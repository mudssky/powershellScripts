# Docker 命令速查

## 目录

- [上下文与状态](#上下文与状态)
- [容器](#容器)
- [镜像](#镜像)
- [卷](#卷)
- [网络](#网络)
- [日志与进入容器](#日志与进入容器)
- [Compose 工作流](#compose-工作流)

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

本仓库开发容器入口位于 `scripts/pwsh/devops/start-container.ps1` 与 `config/dockerfiles/compose/`。在该仓库内优先使用仓库入口；在独立项目中按项目自己的 compose 约定执行。
