# n8n Compose

这个目录提供 n8n 的 Docker Compose 部署模板。它只启动 n8n 应用容器，数据库复用系统已有 PostgreSQL，模式与 `self-hosted/forgejo` 一致。

## 文件说明

- `compose.yaml`：n8n 应用服务模板。
- `.env.example`：可复制的环境变量示例。
- `.gitignore`：忽略本地 `.env` 与运行数据目录。

## 默认约定

- HTTP：宿主机 `5678` -> 容器 `5678`
- PostgreSQL：`host.docker.internal:5432`
- 数据库名：`n8n`
- 数据库用户：`postgres`
- 数据库密码：`12345678`
- 应用数据目录：默认 `self-hosted/n8n/data/n8n`，macOS 长期部署建议放在 `/Volumes/Data/docker_data/n8n`

## 准备环境变量

```bash
cp self-hosted/n8n/.env.example self-hosted/n8n/.env
```

长期使用前，至少检查：

- `N8N_HOST`
- `N8N_PROTOCOL`
- `N8N_SECURE_COOKIE`
- `N8N_WEBHOOK_URL`
- `N8N_ENCRYPTION_KEY`
- `N8N_DB_HOST`
- `N8N_DB_NAME`
- `N8N_DB_USER`
- `N8N_DB_PASSWORD`
- `N8N_DATA_PATH`

`N8N_ENCRYPTION_KEY` 用于加密 n8n 凭据。首次正式启动前必须替换为长随机字符串，并妥善备份；服务已经使用后不要随意更换，否则历史凭据可能无法解密。

本机通过 HTTP 访问时，`N8N_SECURE_COOKIE` 需要保持为 `false`，否则登录页会提示 secure cookie 与非安全 URL 不匹配。后续如果改成 HTTPS 反向代理入口，再把它改回 `true`。

## 准备 PostgreSQL 数据库

Compose 不会启动 PostgreSQL，也不会自动创建数据库。首次启动前需要在共享 PostgreSQL 中准备 `n8n` 数据库。

如果宿主机已经有 `createdb`：

```bash
PGPASSWORD=12345678 createdb -h localhost -p 5432 -U postgres n8n
```

如果使用仓库共享 PostgreSQL 容器：

```bash
docker exec -it postgre createdb -U postgres n8n
```

如果数据库已经存在，可以跳过这一步。

## 准备数据目录

n8n 官方镜像会把运行数据写入 `/home/node/.n8n`。首次启动前建议显式创建目录，避免 Docker 自动创建 root-owned 目录带来后续维护困扰。

默认仓库内路径：

```bash
mkdir -p self-hosted/n8n/data/n8n
```

macOS 上如果使用 `start-container.ps1` 同款数据盘，可以在 `.env` 中配置：

```bash
N8N_DATA_PATH=/Volumes/Data/docker_data/n8n
```

并准备目录：

```bash
mkdir -p /Volumes/Data/docker_data/n8n
```

## 启动

```bash
docker compose \
  --env-file self-hosted/n8n/.env \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  up -d
```

启动后访问：

```text
http://localhost:5678/
```

## 查看状态和日志

```bash
docker compose \
  --env-file self-hosted/n8n/.env \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  ps

docker compose \
  --env-file self-hosted/n8n/.env \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  logs -f --tail=200 n8n
```

## 停止

```bash
docker compose \
  --env-file self-hosted/n8n/.env \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  down
```

`down` 不会删除 `data/n8n`，应用数据会保留在本目录下。

## 升级

如果使用 `latest` 镜像，可以按下面方式拉取并重建：

```bash
docker compose \
  --env-file self-hosted/n8n/.env \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  pull

docker compose \
  --env-file self-hosted/n8n/.env \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  up -d
```

长期使用建议把 `N8N_IMAGE` 固定到明确版本，升级前先备份 PostgreSQL 数据库和 `N8N_DATA_PATH`。

## 配置检查

修改 `.env` 后可以先展开配置：

```bash
docker compose \
  --env-file self-hosted/n8n/.env \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  config
```

如果只想验证模板默认值，也可以直接用 `.env.example`：

```bash
docker compose \
  --env-file self-hosted/n8n/.env.example \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  config
```
