# Forgejo 自托管运维

## 关键路径

- 目录：`self-hosted/forgejo/`
- 说明文档：`self-hosted/forgejo/README.md`
- Compose 模板：`self-hosted/forgejo/compose.yaml`
- 环境示例：`self-hosted/forgejo/.env.example`
- 私有环境：`self-hosted/forgejo/.env`
- 本机数据盘：通常为 `/Volumes/Data/docker_data/forgejo`
- 本机 SSH alias：`forgejo-macmini`

不要输出 `.env`、数据盘 `custom/conf/app.ini` 中的真实数据库密码、internal token、JWT secret、SSH host key、用户 token 或其他私密值。

## 服务边界

- Forgejo compose 只管理 Forgejo 应用容器，不启动 PostgreSQL。
- PostgreSQL 复用宿主机共享服务，容器内默认通过 `host.docker.internal:5432` 访问。
- Linux Docker Engine 依赖 compose 中的 `host.docker.internal:host-gateway`。
- macmini 本机长期数据不放仓库目录，使用 `FORGEJO_DATA_PATH=/Volumes/Data/docker_data/forgejo`。
- 当前默认访问入口：
  - Web：`http://macmini:30001/`
  - SSH：`ssh://git@macmini:32222/<owner>/<repo>.git`

## 常用命令

从仓库根目录执行：

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

docker compose \
  --env-file self-hosted/forgejo/.env \
  -f self-hosted/forgejo/compose.yaml \
  --project-directory self-hosted/forgejo \
  up -d --force-recreate forgejo
```

模板检查使用 `.env.example`，避免依赖本机私有配置：

```bash
docker compose \
  --env-file self-hosted/forgejo/.env.example \
  -f self-hosted/forgejo/compose.yaml \
  --project-directory self-hosted/forgejo \
  config
```

## 数据目录和配置修改

- 修改 `self-hosted/forgejo/.env` 前，按项目规则创建同目录时间戳 `.bak`。
- 修改数据盘上的 `custom/conf/app.ini` 前，也创建同目录时间戳 `.bak`。
- 数据迁移到新路径时：
  1. 停止 Forgejo 容器。
  2. 使用 `rsync -a` 复制旧数据，保留权限和时间戳。
  3. 更新 `FORGEJO_DATA_PATH`。
  4. 重建容器。
  5. 用 `docker inspect forgejo` 验证 `/var/lib/gitea` 的 mount source。
- 不删除旧 `data/`、volume 或数据盘目录，除非用户明确要求。

## SSH 运维

- 对外 SSH 端口默认是 `32222`，容器内监听仍是 `2222`。
- 本机 `~/.ssh/config` 可使用：

```sshconfig
Host forgejo-macmini
  HostName macmini
  Port 32222
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

- 改 SSH 端口时需要同步：
  - `self-hosted/forgejo/compose.yaml`
  - `self-hosted/forgejo/.env.example`
  - `self-hosted/forgejo/.env`
  - 数据盘 `custom/conf/app.ini` 中 `SSH_PORT`
  - `~/.ssh/config`
  - `~/.ssh/known_hosts`
- `SSH_LISTEN_PORT` 通常保持容器内 `2222`，不要误改成宿主机端口。

## Pull Mirror

Forgejo 本身代码镜像建议创建 Pull Mirror：

- 上游：`https://codeberg.org/forgejo/forgejo.git`
- 本地仓库：`mudssky/forgejo`
- 同步间隔：`24h`

可通过 Web UI 创建，也可用 API `/api/v1/repos/migrate` 创建 `mirror=true` 的迁移仓库。自动化时：

- 优先生成短期 token 完成操作，操作后删除 token。
- 不在日志、文档、提交信息或最终答复输出 token。
- 创建后验证：
  - 页面可访问：`http://macmini:30001/mudssky/forgejo`
  - API 返回 `mirror=true`
  - `original_url` 指向 Codeberg 上游
  - `git ls-remote` 能读到默认分支

本机代理可能拦截 `macmini` 并返回 `502`，排查 Git HTTP 访问时可临时绕过：

```bash
NO_PROXY='*' git ls-remote http://macmini:30001/mudssky/forgejo.git
```

## 常见排查

- Web 返回安装页：检查数据目录是否挂错，尤其是 `FORGEJO_DATA_PATH` 是否指向已有数据盘目录。
- 数据库连接失败：确认宿主机 PostgreSQL 监听 `5432`，并检查 `.env` 中数据库主机、库名、用户变量。
- SSH clone 端口错误：检查数据盘 `custom/conf/app.ini` 中 `SSH_PORT`，它会影响页面和 API 返回的 clone URL。
- SSH 连接 `Permission denied (publickey)`：网络和端口通常已通，下一步检查用户公钥是否添加到 Forgejo 账号。
- `macmini` HTTP/Git 请求返回 `502`：优先检查本机代理绕过规则，尤其是 `macmini`、`*.ts.net` 和 `100.64.0.0/10`。

## 验证清单

```bash
docker compose \
  --env-file self-hosted/forgejo/.env.example \
  -f self-hosted/forgejo/compose.yaml \
  --project-directory self-hosted/forgejo \
  config

curl --noproxy '*' -sS --max-time 10 http://macmini:30001/api/v1/repos/mudssky/forgejo

nc -vz -w 5 macmini 32222
```

模板或文档变更后运行：

```bash
pnpm qa
```
