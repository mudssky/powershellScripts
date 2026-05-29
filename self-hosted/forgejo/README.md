# Forgejo Compose

这个目录提供 Forgejo 的 Docker Compose 部署模板。它只启动 Forgejo 应用容器，数据库复用系统已有 PostgreSQL，模式与 LobeHub external 配置一致。

## 文件说明

- `compose.yaml`：Forgejo rootless 应用服务模板。
- `.env.example`：可复制的环境变量示例。
- `.gitignore`：忽略本地 `.env` 与运行数据目录。

## 默认约定

- HTTP：宿主机 `30001` -> 容器 `3000`
- SSH：宿主机 `2222` -> 容器 `2222`
- PostgreSQL：`host.docker.internal:5432`
- 数据库名：`forgejo`
- 数据库用户：`postgres`
- 数据库密码：`12345678`
- 应用数据目录：默认 `self-hosted/forgejo/data/forgejo`，macOS 长期部署建议放在 `/Volumes/Data/docker_data/forgejo`

## 准备环境变量

```bash
cp self-hosted/forgejo/.env.example self-hosted/forgejo/.env
```

生产或长期使用前，至少检查：

- `FORGEJO_ROOT_URL`
- `FORGEJO_DOMAIN`
- `FORGEJO_SSH_DOMAIN`
- `FORGEJO_DB_HOST`
- `FORGEJO_DB_NAME`
- `FORGEJO_DB_USER`
- `FORGEJO_DB_PASSWORD`
- `FORGEJO_USER_UID`
- `FORGEJO_USER_GID`
- `FORGEJO_DATA_PATH`

## 准备 PostgreSQL 数据库

Compose 不会启动 PostgreSQL，也不会自动创建数据库。首次启动前需要在共享 PostgreSQL 中准备 `forgejo` 数据库。

如果宿主机已经有 `createdb`：

```bash
PGPASSWORD=12345678 createdb -h localhost -p 5432 -U postgres forgejo
```

如果使用仓库共享 PostgreSQL 容器：

```bash
docker exec -it postgre createdb -U postgres forgejo
```

如果数据库已经存在，可以跳过这一步。

## 准备数据目录

rootless 镜像默认以 `FORGEJO_USER_UID=1000` / `FORGEJO_USER_GID=1000` 写入数据目录。首次启动前建议显式创建目录并设置权限。

默认仓库内路径：

```bash
mkdir -p self-hosted/forgejo/data/forgejo
chown -R 1000:1000 self-hosted/forgejo/data/forgejo
```

macOS 上如果使用 `start-container.ps1` 同款数据盘，可以在 `.env` 中配置：

```bash
FORGEJO_DATA_PATH=/Volumes/Data/docker_data/forgejo
```

并准备目录：

```bash
mkdir -p /Volumes/Data/docker_data/forgejo
chown -R 1000:1000 /Volumes/Data/docker_data/forgejo
```

如果本机当前用户不是 `1000:1000`，请同步调整 `.env` 里的 `FORGEJO_USER_UID` / `FORGEJO_USER_GID`。

## 启动

```bash
docker compose \
  --env-file self-hosted/forgejo/.env \
  -f self-hosted/forgejo/compose.yaml \
  --project-directory self-hosted/forgejo \
  up -d
```

启动后访问：

```text
http://localhost:30001/
```

SSH clone 地址默认会使用：

```text
ssh://git@localhost:2222/<owner>/<repo>.git
```

## 查看状态和日志

```bash
docker compose \
  --env-file self-hosted/forgejo/.env \
  -f self-hosted/forgejo/compose.yaml \
  --project-directory self-hosted/forgejo \
  ps

docker compose \
  --env-file self-hosted/forgejo/.env \
  -f self-hosted/forgejo/compose.yaml \
  --project-directory self-hosted/forgejo \
  logs -f --tail=200 forgejo
```

## 停止

```bash
docker compose \
  --env-file self-hosted/forgejo/.env \
  -f self-hosted/forgejo/compose.yaml \
  --project-directory self-hosted/forgejo \
  down
```

`down` 不会删除 `data/forgejo`，应用数据会保留在本目录下。

## 配置检查

修改 `.env` 后可以先展开配置：

```bash
docker compose \
  --env-file self-hosted/forgejo/.env \
  -f self-hosted/forgejo/compose.yaml \
  --project-directory self-hosted/forgejo \
  config
```

如果只想验证模板默认值，也可以直接用 `.env.example`：

```bash
docker compose \
  --env-file self-hosted/forgejo/.env.example \
  -f self-hosted/forgejo/compose.yaml \
  --project-directory self-hosted/forgejo \
  config
```
