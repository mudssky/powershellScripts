## 目标
- 用 `docker-compose.yml` 统一管理并启动 `start-container.ps1` 中的各服务，功能等价覆盖：重启策略、日志、数据目录、健康检查、GPU 与现有副本集。
- 在 Windows 11 + Docker Desktop 环境下可直接使用，路径与变量通过 `.env` 控制。

## 总体方案
- 在 `config/dockerfiles/compose/` 新增一个统一的 `docker-compose.yml`，为每个服务设置 `profiles`（与 `ServiceName` 对齐）。
- 新增 `.env` 文件，提供 `DATA_PATH`、`DEFAULT_USER`、`DEFAULT_PASSWORD`、`RESTART_POLICY` 等变量。
- 改造 `start-container.ps1`：根据 `ServiceName` 注入变量后执行 `docker compose -f config/dockerfiles/compose/docker-compose.yml --profile <ServiceName> up -d`。
- 保留并复用现有 `mongo-repl.compose.yml` 以支持 `mongodb-replica`；脚本遇到该服务时直接调用它。

## 目录结构
- `config/dockerfiles/compose/docker-compose.yml`
- `config/dockerfiles/compose/.env`
- 复用：`config/dockerfiles/compose/mongo-repl.compose.yml`

## 参数映射
- `DataPath` → `.env: DATA_PATH`，Compose 中用 `${DATA_PATH}/service/...`
- `DefaultUser`、`DefaultPassword` → `.env: DEFAULT_USER/DEFAULT_PASSWORD`，分别映射到各服务的环境变量（如 MinIO、Mongo、Postgres）。
- `RestartPolicy` → Compose `restart: ${RESTART_POLICY:-unless-stopped}`。
- `$commonParams` 日志 → Compose `logging.driver: json-file`、`options.max-size: 10m`、`options.max-file: "3"`。
- Postgres 健康检查 → Compose `healthcheck`。

## Compose 示例（可直接落地到统一文件）
```yaml
version: "3.8"
services:
  redis:
    image: redis:latest
    container_name: redis-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    ports: ["6379:6379"]
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["redis"]

  postgre:
    image: postgres:latest
    container_name: postgre-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    environment:
      POSTGRES_PASSWORD: ${DEFAULT_PASSWORD:-12345678}
      TZ: "Asia/Shanghai"
    ports: ["5432:5432"]
    volumes:
      - "${DATA_PATH}/postgresql/data:/var/lib/postgresql/data"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["postgre"]

  minio:
    image: bitnami/minio:latest
    container_name: minio-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    environment:
      MINIO_ROOT_USER: ${DEFAULT_USER:-root}
      MINIO_ROOT_PASSWORD: ${DEFAULT_PASSWORD:-12345678}
    ports: ["9000:9000", "9001:9001"]
    volumes:
      - "${DATA_PATH}/minio:/bitnami/minio/data"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["minio"]

  mongodb:
    image: mongo:8
    container_name: mongodb-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    ports: ["27017:27017"]
    volumes:
      - "${DATA_PATH}/mongodb:/data/db"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["mongodb"]

  nacos:
    image: nacos/nacos-server:latest
    container_name: nacos-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    environment:
      MODE: standalone
    ports: ["8848:8848"]
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["nacos"]

  rabbitmq:
    image: rabbitmq:latest
    container_name: rabbitmq-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    ports: ["5672:5672", "15672:15672"]
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["rabbitmq"]

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    ports: ["39090:9090"]
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["prometheus"]

  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    ports: ["35678:5678"]
    volumes:
      - "${DATA_PATH}/n8n:/home/node/.n8n"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["n8n"]

  noco:
    image: nocodb/nocodb:latest
    container_name: noco-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    ports: ["35080:8080"]
    volumes:
      - "${DATA_PATH}/nocodb:/usr/app/data"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["noco"]

  crawl4ai:
    image: unclecode/crawl4ai:latest
    container_name: crawl4ai-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    ports: ["11235:11235"]
    shm_size: "1g"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["crawl4ai"]

  pageSpy:
    image: ghcr.io/huolalatech/page-spy-web:latest
    container_name: pageSpy-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    ports: ["6752:6752"]
    volumes:
      - "${DATA_PATH}/pageSpy/log:/app/log"
      - "${DATA_PATH}/pageSpy/data:/app/data"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["pageSpy"]

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    ports: ["38181:8080"]
    volumes:
      - "/:/rootfs:ro"
      - "/var/run:/var/run:ro"
      - "/sys:/sys:ro"
      - "/var/lib/docker/:/var/lib/docker:ro"
      - "/dev/disk/:/dev/disk:ro"
    privileged: true
    devices:
      - "/dev/kmsg:/dev/kmsg"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["cadvisor"]

  one-api:
    image: justsong/one-api:latest
    container_name: one-api-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    environment:
      TZ: "Asia/Shanghai"
    ports: ["39010:3000"]
    volumes:
      - "${DATA_PATH}/one-api:/data"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["one-api"]

  new-api:
    image: calciumion/new-api:latest
    container_name: new-api-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    environment:
      TZ: "Asia/Shanghai"
    ports: ["3000:3000"]
    volumes:
      - "${DATA_PATH}/new-api:/data"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["new-api"]

  kokoro-fastapi-cpu:
    image: ghcr.io/remsky/kokoro-fastapi-cpu:latest
    container_name: kokoro-fastapi-dev
    restart: ${RESTART_POLICY:-unless-stopped}
    ports: ["38880:8880"]
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles: ["kokoro-fastapi-cpu"]
```

## GPU 服务支持
- `kokoro-fastapi-gpu` 需要 NVIDIA 容器工具链。两种实现方式：
  - Compose v2 支持设备预留：在服务下添加 `deploy.resources.reservations.devices`（capabilities: [gpu]），或使用运行时环境变量组合；
  - 若本机 Compose 不支持 GPU 字段，则保留脚本对该服务的 `docker run --gpus all` 启动。

## `.env` 示例
```env
DATA_PATH=C:/docker_data
DEFAULT_USER=root
DEFAULT_PASSWORD=12345678
RESTART_POLICY=unless-stopped
```

## 脚本改造要点
- 解析 `ServiceName` → 设置临时环境变量（或写入 `.env`），然后执行：
  - `docker compose -f config/dockerfiles/compose/docker-compose.yml --profile <ServiceName> up -d`
- `ServiceName = mongodb-replica` 时：
  - 直接执行 `docker compose -p mongo-repl-dev -f config/dockerfiles/compose/mongo-repl.compose.yml up -d`

## 验证方案
- 语法检查：`docker compose -f ... config`
- 启动单服务：`docker compose -f ... --profile redis up -d`
- 停止：`docker compose -f ... --profile redis down`
- 检查日志与重启策略：`docker inspect <container>` 查看 `LogPath` 与 `RestartPolicy`。

## 风险与兼容性
- Windows 路径：Docker Desktop 支持 `C:/...` 与 `C:\...`，统一用前者更稳妥。
- GPU：不同 Compose 版本对 GPU 字段支持差异较大，必要时对 GPU 服务沿用 CLI 方式。
- 网络：当前脚本未启用自定义网络，Compose 使用默认网络即可，后续如需隔离可增设。

## 下一步
- 我将按上述方案新增统一 Compose 与 `.env`，并改造 `start-container.ps1` 为 Compose 包装器，逐个服务验证启动与等价行为。请确认后执行。