# Forgejo 部署 Compose

## Goal

为 Forgejo 增加一套可维护的 Docker Compose 部署模板，复用系统已经存在的 PostgreSQL，而不是在 Forgejo compose 中再启动一个新的 PostgreSQL 容器。

## Requirements

- 新增 Forgejo 部署用 compose 文件。
- Compose 模板放在仓库根目录 `self-hosted/forgejo`。
- Forgejo 默认对外 HTTP 端口沿用旧 Gitea 配置习惯，使用宿主机 `30001`。
- Forgejo 默认 SSH 端口使用宿主机 `2222` 映射到容器内 `2222`，避免占用宿主机 `22`。
- Forgejo 必须按 LobeHub external 模式复用宿主机 PostgreSQL：
  - 默认连接 `host.docker.internal:5432`
  - 默认数据库名使用 `forgejo`
  - 默认数据库用户沿用共享 PostgreSQL 常见默认 `postgres`
  - 默认密码沿用仓库现有本地示例 `12345678`
- Compose 模板不得包含 Forgejo 专用 PostgreSQL 服务，避免与系统共享 PostgreSQL 产生重复数据源。
- Forgejo 数据目录需要持久化到当前部署目录下的本地路径或命名 volume。
- 需要提供可复制的环境变量示例，便于覆盖镜像版本、端口、数据库连接、站点 URL、SSH 域名等部署差异。
- 文档需要说明 PostgreSQL 数据库需要提前存在，或给出创建数据库的提示。
- 不修改本机私有 `.env.local` / `*.local.*` 配置文件。

## Acceptance Criteria

- [x] 仓库中存在 Forgejo compose 模板，能通过 `docker compose ... config` 成功展开。
- [x] 模板只启动 Forgejo 应用服务，不启动内置 PostgreSQL 服务。
- [x] 模板通过 `FORGEJO__database__DB_TYPE=postgres`、`FORGEJO__database__HOST`、`FORGEJO__database__NAME`、`FORGEJO__database__USER`、`FORGEJO__database__PASSWD` 配置外部 PostgreSQL。
- [x] 默认数据库配置参考 LobeHub 的宿主机 PostgreSQL 模式，使用 `host.docker.internal:5432`。
- [x] 默认 HTTP 端口为 `30001`，默认 SSH 端口为 `2222`。
- [x] Linux Docker Engine 场景下补齐 `host.docker.internal:host-gateway`。
- [x] 提供 `.env.example` 和 README，说明启动、查看日志、停止、数据库初始化前置条件和常见覆盖项。
- [x] 根目录 `pnpm qa` 通过，或记录无法执行的原因。

## Open Questions

- 无。

## Notes

- 仓库证据：
  - `ai/self-hosted/lobehub/docker-compose.yml` 默认连接外部 PostgreSQL / Redis / RustFS。
  - `ai/self-hosted/lobehub/.env.example` 使用 `DATABASE_URL=postgresql://postgres:12345678@host.docker.internal:5432/lobechat`。
  - `config/dockerfiles/compose/docker-compose.yml` 中共享 PostgreSQL 服务名为 `postgre`，默认用户 `postgres`，默认密码 `12345678`。
  - `config/software/gitea/app.ini` 是旧 Windows Gitea 配置，端口为 `30001`，数据库为 sqlite3；本次沿用 HTTP 端口习惯，但不直接迁移该配置。
  - 根目录已存在 `self-hosted` 目录，本次新增 `self-hosted/forgejo`。
- 官方文档证据：
  - Forgejo Docker compose 使用 `codeberg.org/forgejo/forgejo:<version>` 镜像。
  - PostgreSQL 连接通过 `FORGEJO__database__DB_TYPE=postgres`、`FORGEJO__database__HOST`、`FORGEJO__database__NAME`、`FORGEJO__database__USER`、`FORGEJO__database__PASSWD` 配置。
  - rootless 镜像使用 `/var/lib/gitea` 作为数据挂载路径，SSH 端口通常映射到容器内 `2222`。
