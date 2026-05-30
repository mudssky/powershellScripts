# Forgejo 部署 Compose 设计

## Architecture and Boundaries

- 新增根目录 `self-hosted/forgejo` 作为 Forgejo 自托管部署入口。
- 该目录只管理 Forgejo 应用容器，不管理 PostgreSQL 生命周期。
- 数据库复用系统共享 PostgreSQL，连接方式对齐 LobeHub external 模式：
  - 容器内通过 `host.docker.internal:5432` 访问宿主机 PostgreSQL。
  - Linux Docker Engine 通过 `extra_hosts: host.docker.internal:host-gateway` 补齐宿主机别名。
- 配置边界：
  - `compose.yaml` 保存服务结构、端口映射、挂载、环境变量白名单与默认值。
  - `.env.example` 保存可复制的部署变量示例，不写入真实私密配置。
  - `README.md` 说明数据库前置条件、启动、日志、停止、配置覆盖和端口语义。

## Compose Contract

- 服务名：`forgejo`。
- 镜像：默认使用官方 `codeberg.org/forgejo/forgejo:15-rootless`，允许通过 `FORGEJO_IMAGE` 覆盖。
- 数据挂载：
  - rootless 镜像使用 `/var/lib/gitea`。
  - 宿主机默认挂载 `./data/forgejo:/var/lib/gitea`。
- 端口：
  - HTTP：`${FORGEJO_HTTP_PORT:-30001}:3000`。
  - SSH：`${FORGEJO_SSH_PORT:-2222}:2222`。
- 数据库环境变量：
  - `FORGEJO__database__DB_TYPE=postgres`
  - `FORGEJO__database__HOST=${FORGEJO_DB_HOST:-host.docker.internal:5432}`
  - `FORGEJO__database__NAME=${FORGEJO_DB_NAME:-forgejo}`
  - `FORGEJO__database__USER=${FORGEJO_DB_USER:-postgres}`
  - `FORGEJO__database__PASSWD=${FORGEJO_DB_PASSWORD:-12345678}`
  - `FORGEJO__database__SSL_MODE=${FORGEJO_DB_SSL_MODE:-disable}`
- 服务基础配置：
  - `USER_UID` / `USER_GID` 默认 `1000`。
  - `FORGEJO__server__ROOT_URL` 默认 `http://localhost:30001/`。
  - `FORGEJO__server__SSH_DOMAIN` 默认 `localhost`。
  - `FORGEJO__server__SSH_PORT` 默认 `2222`。
  - `FORGEJO__server__START_SSH_SERVER=true`，使用容器内置 SSH 服务。

## Compatibility and Migration Notes

- 旧 `config/software/gitea/app.ini` 是 Windows Gitea 本机配置，使用 sqlite3；本设计不迁移已有数据。
- HTTP 端口沿用旧 Gitea 的 `30001`，减少访问习惯变化。
- SSH 不沿用宿主机 `22`，默认改为 `2222`，避免和宿主机 SSH 服务冲突。
- 共享 PostgreSQL 不会自动创建 `forgejo` 数据库；README 需要给出 `createdb` / `psql` 示例。

## Trade-offs

- 不内置 PostgreSQL：
  - 优点：避免重复数据库实例，符合现有 LobeHub external 模式。
  - 代价：首次部署前需要手动创建数据库或由现有数据库管理流程创建。
- 使用 rootless 镜像：
  - 优点：默认权限边界更收敛，符合官方 Docker rootless compose 示例。
  - 代价：数据目录权限需要与 `USER_UID` / `USER_GID` 匹配。

## Operational and Rollback Notes

- 回滚只需要停止 `self-hosted/forgejo` compose 项目，并保留 `data/forgejo` 数据目录。
- 若配置错误导致启动失败，优先执行 `docker compose --env-file .env -f compose.yaml config` 查看展开后的数据库、端口和 URL。
- 若需要完全清理应用数据，由用户显式删除 `self-hosted/forgejo/data/forgejo`，compose 不自动删除该目录。
