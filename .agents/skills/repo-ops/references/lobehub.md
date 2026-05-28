# LobeHub 自托管运维

## 关键路径

- 目录：`ai/self-hosted/lobehub/`
- 说明文档：`ai/self-hosted/lobehub/README.md`
- Bash 启动脚本：`ai/self-hosted/lobehub/start.sh`
- PowerShell 启动脚本：`ai/self-hosted/lobehub/start.ps1`
- 默认 Compose：`docker-compose.yml`
- 默认环境：`.env`
- internal 回滚模式：`docker-compose.with-internal-db.yml`、`.env.with-internal-services`

不要输出 `.env` 中的真实密钥、数据库密码、S3 secret 或 OAuth secret。

## 模式选择

- `external` 是默认模式，只编排 LobeChat 应用侧服务，并连接宿主机共享 PostgreSQL、Redis、RustFS。
- `internal` 是回滚模式，使用项目内置 PostgreSQL、Redis、RustFS 相关 compose 文件。
- 默认 external 模式下，项目自身主要占用 `3210`；宿主机共享服务通常需要 `5432`、`6379`、`9000`、`9001` 可用。

## 常用命令

Bash：

```bash
cd ai/self-hosted/lobehub
bash start.sh start
bash start.sh restart lobe
bash start.sh update lobe
bash start.sh status
bash start.sh logs lobe
bash start.sh stop lobe
bash start.sh down
```

PowerShell：

```powershell
cd ai/self-hosted/lobehub
./start.ps1 -Action start -Mode external
./start.ps1 -Action restart -Service lobe -Mode external
./start.ps1 -Action update -Service lobe -Mode external
./start.ps1 -Action status -Mode external
./start.ps1 -Action logs -Service lobe -Mode external
```

internal 模式示例：

```bash
cd ai/self-hosted/lobehub
bash start.sh start lobe internal
bash start.sh status internal
```

```powershell
cd ai/self-hosted/lobehub
./start.ps1 -Action start -Mode internal
./start.ps1 -Action status -Mode internal
```

## RustFS 与 bucket

- LobeHub 文件数据的 bucket 名通常为 `lobe`，来自 `.env` 的 `RUSTFS_LOBE_BUCKET`。
- `rustfs-init` 用于创建 bucket 和访问策略。
- 如果 RustFS 可用但初始化失败，可重跑：

```bash
cd ai/self-hosted/lobehub
docker compose up --force-recreate rustfs-init
```

不建议直接拷贝 Docker volume 底层目录做迁移，优先走 bucket 层导出和导入。

## 常见排查

- 数据库连接失败：确认宿主机 PostgreSQL 是否监听 `5432`，再检查 `.env` 中 `DATABASE_URL` 的主机、用户名、库名。
- Redis 连接失败：确认宿主机 Redis 是否监听 `6379`，再检查 `.env` 中 `REDIS_URL`。
- RustFS 初始化失败：先确认 `http://host.docker.internal:9000/health` 对容器可访问，再重跑 `rustfs-init`。
- 浏览器中文件地址打不开：检查 `.env` 中 `APP_URL` 和 `S3_PUBLIC_DOMAIN` 是否是浏览器可访问地址，不要把容器内专用的 `host.docker.internal` 当作浏览器公共域名。

## 操作边界

- `down` 会移除当前 compose 管理的容器，但通常不删除 volume；删除 volume 或迁移数据前必须获得用户明确确认。
- external 模式不是数据库服务启动器；如果 PostgreSQL、Redis、RustFS 不存在，应先定位宿主机共享服务，而不是修改 LobeHub compose 盲目补服务。
- 生产或长期数据迁移前，先确认 bucket、数据库、Redis 和 `.env` 之间的一致性。
