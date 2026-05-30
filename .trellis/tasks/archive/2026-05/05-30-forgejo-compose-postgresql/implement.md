# Forgejo 部署 Compose 实施计划

## Checklist

- [x] 创建 `self-hosted/forgejo` 目录。
- [x] 新增 `compose.yaml`，只定义 Forgejo 应用服务并连接外部 PostgreSQL。
- [x] 新增 `.env.example`，提供镜像、端口、数据库、站点 URL、UID/GID 示例。
- [x] 新增 `.gitignore`，忽略本地 `.env` 和运行数据目录。
- [x] 新增 `README.md`，说明数据库初始化、启动、日志、停止和常见覆盖项。
- [x] 验证 `docker compose --env-file self-hosted/forgejo/.env.example -f self-hosted/forgejo/compose.yaml --project-directory self-hosted/forgejo config`。
- [x] 运行根目录 `pnpm qa`。

## Validation Commands

```bash
docker compose \
  --env-file self-hosted/forgejo/.env.example \
  -f self-hosted/forgejo/compose.yaml \
  --project-directory self-hosted/forgejo \
  config

pnpm qa
```

## Risky Files and Rollback Points

- `self-hosted/forgejo/compose.yaml`
  - 风险：端口、数据目录或 Forgejo 环境变量配置错误会影响首次启动。
  - 回滚：删除新目录即可，不影响已有服务。
- `self-hosted/forgejo/.env.example`
  - 风险：示例默认值可能被误用于生产环境。
  - 回滚：修正文档和示例注释，不涉及真实密钥。

## Pre-start Review Gate

- PRD 已确认：
  - 数据库复用 LobeHub 同款宿主机 PostgreSQL 模式。
  - HTTP 默认端口 `30001`，SSH 默认端口 `2222`。
  - 目录为根目录 `self-hosted/forgejo`。
- 用户确认规划后，执行 `python ./.trellis/scripts/task.py start 05-30-forgejo-compose-postgresql` 再进入实现。
