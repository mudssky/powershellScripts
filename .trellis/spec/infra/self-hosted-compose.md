# Self-Hosted Compose Spec

> 本规范记录根目录 `self-hosted/*` 自托管服务的 compose、环境变量和数据目录边界。

## Scenario: Self-Hosted App Compose with External Services

### 1. Scope / Trigger

- Trigger: 新增或修改 `self-hosted/<service>/compose.yaml`、`.env.example`、README，或让自托管服务复用宿主机数据库、缓存、对象存储等共享基础设施。
- Scope: `self-hosted/<service>` 目录只维护应用服务自己的 compose 入口、示例环境变量和运行说明；共享基础设施生命周期不放在应用 compose 中。
- Design intent: 自托管应用可以独立启停，同时复用 `start-container.ps1` 管理的数据盘与宿主机共享服务，避免每个应用各自启动一套 PostgreSQL / Redis / S3。

### 2. Signatures

- Compose:
  - `docker compose --env-file self-hosted/<service>/.env -f self-hosted/<service>/compose.yaml --project-directory self-hosted/<service> up -d`
  - `docker compose --env-file self-hosted/<service>/.env.example -f self-hosted/<service>/compose.yaml --project-directory self-hosted/<service> config`
- Data path:
  - `FORGEJO_DATA_PATH=/Volumes/Data/docker_data/forgejo` on macOS long-running deployments.
  - Default macOS data root follows `scripts/pwsh/devops/start-container.ps1`: `/Volumes/Data/docker_data`.
- Forgejo external PostgreSQL:
  - `FORGEJO_DB_HOST=host.docker.internal:5432`
  - `FORGEJO_DB_NAME=forgejo`
  - `FORGEJO_DB_USER=postgres`
  - `FORGEJO_DB_PASSWORD=<local secret>`

### 3. Contracts

- `compose.yaml` must be runnable with `.env.example` and should include safe defaults for every interpolated variable.
- Local `.env`, `.env.local`, timestamped `.env.*.bak`, and runtime `data/` directories must be ignored by the service-local `.gitignore`.
- Host-shared services must be reached through `host.docker.internal` and compose must include:
  - `extra_hosts: ["host.docker.internal:host-gateway"]`
- Long-running app data should be controlled by a service-specific `*_DATA_PATH` variable instead of hardcoding `./data/...`.
- On macOS, production-ish local data should prefer `/Volumes/Data/docker_data/<service>` so the repository directory does not become the primary data store.

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| `.env` missing | `.env.example` still allows `docker compose ... config` to expand |
| app needs PostgreSQL | app compose does not start a second PostgreSQL service |
| Linux Docker Engine lacks host alias | `extra_hosts` provides `host.docker.internal` |
| data path changed | stop service, copy data with metadata preservation, update `.env`, recreate service, verify mount source |
| local `.env` edited | create a readable timestamped `.bak` in the same directory before modification |

### 5. Good/Base/Bad Cases

- Good: `self-hosted/forgejo/compose.yaml` uses `FORGEJO_DATA_PATH` and points local macOS data to `/Volumes/Data/docker_data/forgejo`.
- Good: `.env.example` documents the default repo-local data path and the macOS data-disk override.
- Base: `docker compose --env-file self-hosted/forgejo/.env.example ... config` expands without a real `.env`.
- Bad: Commit generated `data/`, `.env`, `.env.*.bak`, private app.ini, SSH host keys, JWT keys, or uploaded files.
- Bad: Add a PostgreSQL service inside an app compose when the app is intended to reuse host PostgreSQL.

### 6. Tests Required

- Run `docker compose --env-file <service>/.env.example -f <service>/compose.yaml --project-directory <service> config`.
- For local deployment changes, run `docker inspect <container>` and verify the app data mount source.
- Run root `pnpm qa` after committed template or documentation changes.

### 7. Wrong vs Correct

#### Wrong

```yaml
services:
  forgejo:
    volumes:
      - ./data/forgejo:/var/lib/gitea

  db:
    image: postgres:17
```

问题：仓库目录变成长期数据目录，并且应用 compose 重新启动 PostgreSQL，偏离共享基础设施边界。

#### Correct

```yaml
services:
  forgejo:
    volumes:
      - ${FORGEJO_DATA_PATH:-./data/forgejo}:/var/lib/gitea
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

理由：模板仍可开箱验证，本机部署可把数据落到 `/Volumes/Data/docker_data/forgejo`，数据库连接继续复用宿主机共享 PostgreSQL。
