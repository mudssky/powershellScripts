# n8n 自托管运维

## 关键路径

- 目录：`self-hosted/n8n/`
- 说明文档：`self-hosted/n8n/README.md`
- Compose 模板：`self-hosted/n8n/compose.yaml`
- 环境示例：`self-hosted/n8n/.env.example`
- 私有环境：`self-hosted/n8n/.env`
- 本机数据盘：通常为 `/Volumes/Data/docker_data/n8n`

不要输出 `.env` 中的 `N8N_ENCRYPTION_KEY`、数据库密码、用户凭据、API key、OAuth secret、workflow 内部 secret 或其他私密值。

## 服务边界

- n8n compose 只管理 n8n 应用容器，不启动 PostgreSQL。
- PostgreSQL 复用宿主机共享服务，容器内默认通过 `host.docker.internal:5432` 访问。
- Linux Docker Engine 依赖 compose 中的 `host.docker.internal:host-gateway`。
- macmini 本机长期数据不放仓库目录，使用 `N8N_DATA_PATH=/Volumes/Data/docker_data/n8n`。
- 当前默认访问入口：
  - Web：`http://macmini:5678/`
  - 本机回环：`http://localhost:5678/`

## 常用命令

从仓库根目录执行：

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

docker compose \
  --env-file self-hosted/n8n/.env \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  up -d --force-recreate n8n
```

模板检查使用 `.env.example`，避免依赖本机私有配置：

```bash
docker compose \
  --env-file self-hosted/n8n/.env.example \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  config
```

## 数据目录和配置修改

- 修改 `self-hosted/n8n/.env` 前，按项目规则创建同目录时间戳 `.bak`。
- n8n 数据目录挂载到容器内 `/home/node/.n8n`，本机长期部署默认使用 `/Volumes/Data/docker_data/n8n`。
- 数据迁移到新路径时：
  1. 停止 n8n 容器。
  2. 使用 `rsync -a` 复制旧数据，保留权限和时间戳。
  3. 更新 `N8N_DATA_PATH`。
  4. 重建容器。
  5. 用 `docker inspect n8n` 验证 `/home/node/.n8n` 的 mount source。
- 不删除旧 `data/`、volume、数据库或数据盘目录，除非用户明确要求。

## PostgreSQL

- Compose 不创建数据库；首次启动前需要在共享 PostgreSQL 中准备 `N8N_DB_NAME`，默认是 `n8n`。
- 默认变量：
  - `N8N_DB_HOST=host.docker.internal`
  - `N8N_DB_PORT=5432`
  - `N8N_DB_NAME=n8n`
  - `N8N_DB_USER=postgres`
  - `N8N_DB_SCHEMA=public`
- 不要把 `N8N_DB_PASSWORD` 的真实值写入日志、文档、提交信息或最终答复。
- 本机非 SSL PostgreSQL 不需要向 n8n 传 `DB_POSTGRESDB_SSL_*` 变量；如果误传，可能触发 `The server does not support SSL connections`。

## Webhook 与 Cookie

- `N8N_HOST`、`N8N_PROTOCOL` 和 `N8N_WEBHOOK_URL` 会影响页面和 webhook URL。
- 本机 HTTP 访问时保持 `N8N_SECURE_COOKIE=false`，否则浏览器可能提示 secure cookie 与非安全 URL 不匹配。
- 改成 HTTPS 反向代理入口时，同步更新：
  - `N8N_HOST`
  - `N8N_PROTOCOL`
  - `N8N_WEBHOOK_URL`
  - `N8N_SECURE_COOKIE`
- `N8N_ENCRYPTION_KEY` 必须长期固定并备份；服务使用后不要随意更换，否则历史凭据可能无法解密。

## 常见排查

- Web 提示 secure cookie 错误：本机 HTTP 场景检查 `N8N_SECURE_COOKIE=false`，重建容器后再访问。
- 数据库连接失败：确认宿主机 PostgreSQL 监听 `5432`，并检查 `.env` 中数据库主机、库名、用户变量。
- 日志出现 `The server does not support SSL connections`：检查 compose 展开结果中是否仍存在 `DB_POSTGRESDB_SSL_*` 变量。
- webhook 地址不对：检查 `N8N_WEBHOOK_URL` 是否是浏览器或外部服务可访问的最终入口。
- 页面无法访问但容器运行中：先 `curl --noproxy '*' -I http://localhost:5678/`，再检查本机代理、端口占用和容器日志。

## 验证清单

```bash
docker compose \
  --env-file self-hosted/n8n/.env.example \
  -f self-hosted/n8n/compose.yaml \
  --project-directory self-hosted/n8n \
  config

docker inspect n8n --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'

curl --noproxy '*' -sS -I --max-time 10 http://localhost:5678/
```

模板或文档变更后运行：

```bash
pnpm qa
```
