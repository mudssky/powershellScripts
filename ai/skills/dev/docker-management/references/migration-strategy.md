# Docker 迁移与备份策略

## 目录

- [迁移前总原则](#迁移前总原则)
- [要不要备份](#要不要备份)
- [备份命令](#备份命令)
- [恢复命令](#恢复命令)
- [平台步骤入口](#平台步骤入口)

## 迁移前总原则

1. 先盘点对象，再决定备份范围。
2. 有状态服务先停写，再备份。数据库、对象存储、消息队列等不要在写入中直接打包卷。
3. 每份关键备份至少做一次列表检查；重要数据要在目标运行时做恢复演练。
4. 新运行时启动并验证后，再卸载或清理旧运行时。
5. 公共镜像优先重拉，本地唯一镜像才 `docker save`。

## 要不要备份

| 对象 | 默认是否备份 | 决策依据 | 分支 |
|---|---|---|---|
| 数据卷（named volume / bind mount 数据） | 要 | 有不可再生数据，如数据库、对象存储、队列状态 | 需要：进入卷或目录备份；不需要：记录原因并跳过 |
| compose 配置 + `.env` | 要 | 已在 Git 中版本管理且无本机 secret 时可跳过 | 需要：拷贝配置；不需要：确认仓库可重建 |
| 自建/本地构建镜像 | 视情况 | 仅本机存在且没有 Dockerfile、registry 或构建上下文 | 需要：`docker save`；不需要：目标端重新 build/pull |
| 容器本身 | 否 | 容器应由镜像和 compose 重建 | 通常跳过，只导出必要配置 |
| Docker Desktop 的 WSL 发行版整体 | 可选 | Windows 上想整盘保底或暂存旧数据 | 需要：`wsl --export docker-desktop-data`；不需要：跳过 |

## 备份命令

### 镜像

仅备份无法重新拉取或重新构建的本地镜像。

```bash
docker images
docker save -o my-image.tar my-image:tag
```

多个镜像可以放在同一个 tar 中：

```bash
docker save -o local-images.tar image-a:tag image-b:tag
```

### 命名卷

先停止写入该卷的服务，再打包：

```bash
docker run --rm \
  -v volume_name:/data:ro \
  -v "$PWD:/backup" \
  alpine \
  tar czf /backup/volume_name.tar.gz -C /data .
```

检查备份：

```bash
tar tzf volume_name.tar.gz | head
```

### bind mount 目录

bind mount 本质是宿主目录。停止写入后用文件系统工具复制，保留权限和隐藏文件：

```bash
rsync -a --info=progress2 /path/to/data/ ./backup/data/
```

Windows PowerShell 中可用 `robocopy`，注意它的退出码 `0` 到 `7` 通常都表示成功或部分差异：

```powershell
robocopy C:\data C:\backup\data /MIR /COPY:DAT /DCOPY:DAT
```

### compose 配置和环境文件

优先确认配置已经进 Git。未进 Git 的本机配置单独复制到备份目录，不要提交真实 secret。

```bash
mkdir -p backup/compose
cp compose.yml docker-compose.yml .env .env.local backup/compose/ 2>/dev/null || true
```

### Windows-only：Docker Desktop WSL 发行版保底

这不是常规迁移方式，只适合卸载前保底留档。

```powershell
wsl --list --verbose
wsl --shutdown
wsl --export docker-desktop-data .\docker-desktop-data.tar
```

## 恢复命令

### 镜像

```bash
docker load -i my-image.tar
docker images
```

### 命名卷

先创建卷，再恢复：

```bash
docker volume create volume_name
docker run --rm \
  -v volume_name:/data \
  -v "$PWD:/backup" \
  alpine \
  sh -c 'cd /data && tar xzf /backup/volume_name.tar.gz'
```

### bind mount 目录

把备份目录复制回目标路径，然后确认目标运行时能读写：

```bash
rsync -a ./backup/data/ /path/to/data/
```

### compose 栈

恢复配置后先做语法检查，再启动：

```bash
docker compose config
docker compose pull
docker compose up -d
docker compose ps
```

## 平台步骤入口

- Windows Docker Desktop 迁到 Rancher Desktop：见 `platforms/windows.md`。
- Windows Docker Desktop 迁到 WSL2-CLI + Portainer：见 `platforms/windows.md`。
- macOS / Linux：尚未补充，执行前先查官方迁移和卸载文档。
