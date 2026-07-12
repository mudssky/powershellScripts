# LobeChat Compose 使用说明

这个仓库现在默认只编排 LobeChat 应用侧服务。

外部依赖已经从主 `docker-compose.yml` 中移出：

- ParadeDB / PostgreSQL
- Redis
- RustFS

当前项目仍然保留：

- `lobe`
- `searxng`
- `rustfs-init`

## 默认模式

默认模式使用以下文件：

- `docker-compose.yml`
- `.env`

在这个模式下，LobeChat 会连接宿主机上的共享服务：

- PostgreSQL：`host.docker.internal:5432`
- Redis：`host.docker.internal:6379`
- RustFS API：`host.docker.internal:9000`

其中：

- `S3_ENDPOINT` 用于容器内访问宿主机 RustFS
- `S3_PUBLIC_DOMAIN` 用于浏览器或外部访问对象文件
- 当前默认值是 `http://macmini:9000`

如果你本机不是通过 `macmini` 访问，请同步修改：

- `.env` 里的 `APP_URL`
- `.env` 里的 `S3_PUBLIC_DOMAIN`

启动命令：

```bash
docker compose up -d
```

也可以使用仓库里的启动脚本：

```bash
bash start.sh start
bash start.sh logs lobe
bash start.sh status internal
```

说明：

- `start.sh` 默认是 `external` 模式
- 传入 `internal` 时会自动切到 `docker-compose.with-internal-db.yml + .env.with-internal-services`
- 如果当前磁盘挂载方式不允许直接执行脚本，优先使用 `bash start.sh ...`

查看服务状态：

```bash
docker compose ps
```

查看日志：

```bash
docker compose logs -f --tail=200 lobe
```

数据库容器的进入方式、认证规则、常用查询命令，见：

- [docs/postgres-docker-usage.md](docs/postgres-docker-usage.md)

## 回滚模式

如果要切回“项目内置依赖”版本，使用以下文件：

- `docker-compose.with-internal-db.yml`
- `.env.with-internal-services`

启动命令：

```bash
docker compose -f docker-compose.with-internal-db.yml --env-file .env.with-internal-services up -d
```

PowerShell 下可用：

```powershell
./start.ps1 -Action start -Mode external
./start.ps1 -Action status -Mode internal
./start.ps1 -Action logs -Service lobe -Mode external
```

这会重新使用项目内的：

- ParadeDB / PostgreSQL
- Redis
- RustFS

## rustfs-init

`rustfs-init` 仍然属于当前项目，用来确保 LobeChat 自己的 bucket 和访问策略存在。

如果宿主机 RustFS 已经启动，但 bucket 初始化失败，可以单独重跑：

```bash
docker compose up --force-recreate rustfs-init
```

## RustFS 数据在哪

LobeHub 在 RustFS 里的数据可以分成两层理解。

逻辑层：

- bucket 名是 `lobe`
- 这个名字来自 `.env` 里的 `RUSTFS_LOBE_BUCKET=lobe`
- `rustfs-init` 也会给 `lobe` bucket 设置访问策略

持久化层：

- 当前内置 RustFS 使用的 Docker volume 名是 `lobehub_rustfs-data`
- Docker 记录的挂载点是 `/var/lib/docker/volumes/lobehub_rustfs-data/_data`

可以用下面命令确认：

```bash
docker volume inspect lobehub_rustfs-data
```

更直白地说：

- 你真正关心的 LobeHub 文件数据在 `lobe` bucket
- 当前这份 bucket 数据落在 `lobehub_rustfs-data` 这个 volume 里

不建议直接拷贝底层 volume 目录做迁移，优先走 bucket 层导出/导入。

## RustFS 迁移指南

推荐做法是：

1. 先从旧的内置 RustFS 导出 `lobe` bucket
2. 再启动新的宿主机 RustFS
3. 把导出的 bucket 导入到新 RustFS
4. 最后重跑 `rustfs-init`

### 迁移前确认

- 旧 bucket：`lobe`
- 旧 volume：`lobehub_rustfs-data`
- 新宿主机 RustFS 最终端口：
  - API `9000`
  - Console `9001`
- 新宿主机 RustFS 的 access key / secret key 必须与 `.env` 一致

### 第 1 步：如果旧内置 RustFS 没在运行，先临时启动它

如果你当前旧容器还在运行，这一步可以跳过。

```bash
docker compose -f docker-compose.with-internal-db.yml --env-file .env.with-internal-services up -d network-service rustfs rustfs-init
```

注意：

- 旧内置 RustFS 会占用宿主机 `9000/9001`
- 如果新的宿主机 RustFS 已经先启动了，请先停掉新的，避免端口冲突

### 第 2 步：导出旧 `lobe` bucket 到本地目录

```bash
mkdir -p rustfs-migration

docker run --rm \
  -v "$PWD/rustfs-migration:/backup" \
  minio/mc \
  sh -c 'mc alias set old http://host.docker.internal:9000 admin 1cf7f374 && mc mirror --overwrite old/lobe /backup/lobe'
```

如果你实际使用的 RustFS 凭证不是：

- access key `admin`
- secret key `1cf7f374`

请把命令里的值换成你自己的。

导出成功后，本地会出现：

- `rustfs-migration/lobe`

### 第 3 步：停止旧内置 RustFS

```bash
docker compose -f docker-compose.with-internal-db.yml --env-file .env.with-internal-services stop rustfs rustfs-init network-service
```

### 第 4 步：启动新的宿主机 RustFS

这一步由你或胡子在宿主机完成，但要确保：

- 监听 `9000/9001`
- 使用和 `.env` 一致的 `RUSTFS_ACCESS_KEY` / `RUSTFS_SECRET_KEY`
- 已配置持久化目录或 volume

### 第 5 步：把导出的 `lobe` bucket 导入到新的 RustFS

```bash
docker run --rm \
  -v "$PWD/rustfs-migration:/backup" \
  minio/mc \
  sh -c 'mc alias set new http://host.docker.internal:9000 admin 1cf7f374 && mc mb new/lobe --ignore-existing && mc mirror --overwrite /backup/lobe new/lobe'
```

### 第 6 步：重跑项目里的 `rustfs-init`

这样可以把 bucket 策略重新对齐到当前项目配置。

```bash
docker compose up --force-recreate rustfs-init
```

### 第 7 步：启动当前项目

```bash
docker compose up -d
```

### 迁移完成后的核对项

- LobeChat 里的历史图片和文件可以打开
- 新上传文件可以正常写入
- `rustfs-init` 没有鉴权错误
- `.env` 里的 `S3_PUBLIC_DOMAIN` 仍然是浏览器可访问地址

## 端口要求

默认模式下，这个项目自身只占用：

- `3210`：LobeChat

宿主机共享服务需要提前可用：

- `5432`：PostgreSQL / ParadeDB
- `6379`：Redis
- `9000`：RustFS API
- `9001`：RustFS Console

## 常见排查

### 1. 数据库连不上

检查宿主机 PostgreSQL 是否已启动：

```bash
docker ps --format '{{.Names}}\t{{.Ports}}'
```

确认 `.env` 中的 `DATABASE_URL` 用户名、密码、库名与宿主机 ParadeDB 一致。

### 2. Redis 连不上

确认宿主机 Redis 正在监听 `6379`，并且 `.env` 中的 `REDIS_URL` 没有写错。

### 3. RustFS 初始化失败

先确认宿主机 RustFS 健康检查可访问：

```bash
docker run --rm alpine sh -c 'wget -qO- http://host.docker.internal:9000/health'
```

如果健康检查正常，再重跑：

```bash
docker compose up --force-recreate rustfs-init
```

### 4. 浏览器里文件地址打不开

`host.docker.internal` 主要给容器内访问宿主机使用，宿主机浏览器不一定能直接解析它。

如果页面里资源地址打不开，优先检查 `.env` 中的：

- `S3_PUBLIC_DOMAIN`
- `APP_URL`

把它们改成你本机浏览器可以直接访问的地址即可。

另外还要确认当前 compose 没把 `S3_SET_ACL` 关掉。

- 现在默认配置应当让 `S3_SET_ACL=1`
- 原因是 LobeHub 在 `S3_SET_ACL=0` 时，会回退成基于 `S3_ENDPOINT` 生成预签名预览地址
- 如果你的 `S3_ENDPOINT` 是 `http://host.docker.internal:9000`，那这个地址对容器可用，但对宿主机浏览器通常不可用
- 典型现象就是上传成功后，前端马上拿到 `host.docker.internal` 开头的文件 URL，然后界面报错或显示 `Bad Gateway`

还要注意一个更关键的上传链路差异：

- 当前版本的附件上传会先调用 `upload.createS3PreSignedUrl`
- 这个接口生成的浏览器直传目标，使用的也是 `S3_ENDPOINT`
- 也就是说，`S3_ENDPOINT` 不只是“容器内访问 RustFS”的地址，它还会直接暴露给浏览器
- 如果这里写成 `host.docker.internal`，浏览器通常会在上传前的 `OPTIONS/PUT` 阶段直接失败

当前仓库默认建议改成：

- `S3_ENDPOINT=http://macmini:9000`
- `S3_PUBLIC_DOMAIN=http://macmini:9000`

如果 `macmini` 是这台机器在 Tailscale / MagicDNS 里的稳定地址，推荐统一这样配置。

同时要记得：

- 浏览器侧会直接访问 `S3_ENDPOINT`
- 容器侧也必须能解析 `macmini`
- 当前 compose 使用了 `network_mode: service:network-service`
- 因此主机名映射要加在 `network-service` 上，而不是 `lobe` 上

当前默认做法就是：

- `.env` 中 `S3_ENDPOINT=http://macmini:9000`
- `.env` 中 `S3_PUBLIC_DOMAIN=http://macmini:9000`
- `docker-compose.yml` 里的 `network-service.extra_hosts` 增加 `macmini:host-gateway`

这样同一 Tailnet 里的其它客户端、宿主机浏览器和容器内服务都会统一使用 `macmini`，避免再出现上传直传地址和对外访问地址分裂的问题。

排查时可以直接在宿主机执行：

```bash
python3 - <<'PY'
import socket
for host in ['host.docker.internal', 'localhost']:
    try:
        print(host, socket.gethostbyname(host))
    except Exception as exc:
        print(host, 'ERR', exc)
PY
```

如果 `host.docker.internal` 在宿主机侧解析失败，而浏览器里看到的文件地址又正好是这个域名，根因基本就确定了。
