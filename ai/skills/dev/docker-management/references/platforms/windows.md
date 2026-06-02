# Windows Docker 管理

## 目录

- [三种方案](#三种方案)
- [方案 C：WSL2-CLI + Docker Engine + Portainer](#方案-cwsl2-cli--docker-engine--portainer)
- [Docker Desktop 迁到 Rancher Desktop](#docker-desktop-迁到-rancher-desktop)
- [Docker Desktop 迁到 WSL2-CLI](#docker-desktop-迁到-wsl2-cli)
- [内置配置模板](#内置配置模板)

## 三种方案

### 方案 A：Docker Desktop

适合希望官方集成、GUI、自动升级、低维护成本的用户。商用场景要按 Docker 当前订阅条款确认授权。迁出前不要直接卸载，先按 `../migration-strategy.md` 判断是否需要备份镜像、卷和 compose 配置。

### 方案 B：Rancher Desktop

适合想用开源桌面运行时、同时需要 Kubernetes 或 GUI 管理能力的用户。Windows 上建议优先选择 Moby(dockerd) 引擎以保持 Docker CLI / compose 兼容；containerd 更适合 nerdctl 或 Kubernetes 工作流。

迁移后先确认：

```powershell
docker context ls
docker version
docker compose version
```

### 方案 C：WSL2-CLI + Portainer

适合熟悉 Linux、希望更透明地控制资源、网络、代理和 daemon 配置的用户。Docker Engine 直接安装在 WSL2 发行版里，Portainer CE 提供本机 WebUI。

## 方案 C：WSL2-CLI + Docker Engine + Portainer

### 1. 准备 WSL2

确认 WSL 可用：

```powershell
wsl --version
wsl --status
wsl --list --verbose
```

在 `%UserProfile%\.wslconfig` 使用全局 WSL2 VM 配置。优先按 `../wsl2-config-templates.md` 选择轻量、均衡或高负载模板，并直接复制 `assets/wsl2/*.wslconfig` 中的一个文件。

修改后执行：

```powershell
wsl --shutdown
```

### 2. 配置发行版内 `/etc/wsl.conf`

在目标 WSL 发行版内写入 `/etc/wsl.conf`。在 WSL2 内直接运行 Docker Engine 时，复制 `assets/wsl2/docker-engine.wsl.conf`；只需要 systemd 时，复制 `assets/wsl2/minimal-systemd.wsl.conf`。

保存后在 Windows 侧执行 `wsl --shutdown`，再重新进入发行版。确认 systemd：

```bash
systemctl is-system-running
```

### 3. 安装 Docker Engine

Ubuntu / Debian 系发行版优先使用 Docker 官方 apt 源：

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

启用服务并把当前用户加入 docker 组：

```bash
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker
docker run --rm hello-world
```

Debian 发行版把 apt 源 URL 改成 `https://download.docker.com/linux/debian`，并以官方文档为准。

### 4. 部署 Portainer CE

本机开发默认只绑定 localhost：

```bash
docker volume create portainer_data
docker run -d \
  --name portainer \
  --restart=always \
  -p 127.0.0.1:9443:9443 \
  -p 127.0.0.1:38000:8000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:lts
```

访问 `https://127.0.0.1:9443` 完成初始化。容器内 `8000` 是 Edge Agent 相关端口，示例映射到宿主机 `38000` 以避开常见开发端口；不需要 Edge Agent 时可以不暴露。

Compose 写法：

```yaml
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: always
    ports:
      - "127.0.0.1:9443:9443"
      - "127.0.0.1:38000:8000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data

volumes:
  portainer_data:
```

### 5. 代理与端口策略

代理配置不要依赖某个项目里的脚本。需要代理时，直接按当前环境写入 shell 环境变量、Docker daemon systemd drop-in 或 Docker CLI 容器代理配置。WSL2 mirrored / NAT 的代理地址选择和排障细节见 `../wsl-network-proxy.md`。

当前 shell 临时代理：

```bash
export http_proxy="http://127.0.0.1:7890"
export https_proxy="$http_proxy"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$http_proxy"
```

Docker daemon 拉取代理：

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7890"
Environment="HTTPS_PROXY=http://127.0.0.1:7890"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

新建容器默认代理：

```bash
mkdir -p ~/.docker
cat >~/.docker/config.json <<'EOF'
{
  "proxies": {
    "default": {
      "httpProxy": "http://127.0.0.1:7890",
      "httpsProxy": "http://127.0.0.1:7890",
      "noProxy": "localhost,127.0.0.1,::1"
    }
  }
}
EOF
```

WSL mirrored 网络中，优先使用 `127.0.0.1:<port>` 或 `host.docker.internal:<port>` 访问 Windows 侧代理。旧式解析 `/etc/resolv.conf` nameserver 的代理脚本只适合 NAT 模式，不再作为默认方案。

本机开发服务默认把端口绑定到 `127.0.0.1`：

```yaml
ports:
  - "127.0.0.1:5432:5432"
```

需要局域网访问时，再显式放宽 Docker 端口绑定和 Windows / Hyper-V 防火墙。

## Docker Desktop 迁到 Rancher Desktop

1. 盘点：`docker context ls`、`docker ps -a`、`docker volume ls`、`docker compose ls`。
2. 按 `../migration-strategy.md` 决定备份范围。数据库和对象存储卷默认备份。
3. 停止写入旧容器：`docker compose down` 或逐个停止服务。
4. 安装并启动 Rancher Desktop，容器引擎优先选择 Moby(dockerd)。
5. 确认 Docker CLI 指向 Rancher Desktop：

   ```powershell
   docker context ls
   docker info
   docker compose version
   ```

6. 恢复镜像、卷和 compose 配置。
7. 启动 compose 栈并验证数据、日志和端口。
8. 确认 Rancher Desktop 可替代后，再卸载 Docker Desktop。

卸载 Docker Desktop 可用 GUI，也可用官方安装器：

```powershell
& 'C:\Program Files\Docker\Docker\Docker Desktop Installer.exe' uninstall
```

如需卸载但保留 Docker Desktop 底层数据作临时保底，使用官方支持的 `-keep-data` 路径并在清理前再次确认。

## Docker Desktop 迁到 WSL2-CLI

1. 先完成本文件「方案 C」安装配置，确保 `docker run --rm hello-world` 成功。
2. 在 Docker Desktop 运行时盘点工作负载：

   ```powershell
   docker context ls
   docker ps -a
   docker volume ls
   docker images
   ```

3. 按 `../migration-strategy.md` 备份需要保留的卷、镜像、compose 和 `.env`。
4. 停止 Docker Desktop 管理的容器，避免继续写旧数据。
5. 切换到 WSL2 发行版内运行恢复命令：`docker load`、卷 tar 恢复、bind mount 目录复制。
6. 用目标运行时启动 compose：

   ```bash
   docker compose config
   docker compose up -d
   docker compose ps
   ```

7. 验证数据库连接、对象存储 bucket、应用日志、Portainer 页面和端口绑定。
8. 确认不再需要 Docker Desktop 后，再卸载。

Docker Desktop 卸载后如需清理残留 WSL 发行版，先确认已备份或不再需要：

```powershell
wsl --list --verbose
wsl --unregister docker-desktop
wsl --unregister docker-desktop-data
```

`wsl --unregister` 会删除对应发行版数据，执行前必须确认迁移完成或已经导出保底。

## 内置配置模板

本 skill 自带可复制模板，不依赖任何仓库文件：

- `../wsl2-config-templates.md`：WSL2 模板选择说明和复制命令。
- `../../assets/wsl2/`：轻量、均衡、高负载 `.wslconfig` 文件，以及 Docker Engine 推荐 `/etc/wsl.conf` 文件。
- `../daily-ops.md`：日志轮转、代理、端口绑定和清理命令。
- `../migration-strategy.md`：镜像、卷、bind mount、compose 配置的备份/恢复命令。

跨平台迁移命令见 `../migration-strategy.md`，日常运维见 `../daily-ops.md`。
