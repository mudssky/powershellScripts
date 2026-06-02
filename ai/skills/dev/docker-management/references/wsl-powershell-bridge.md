# Windows PowerShell 调用 WSL Docker Engine

## 结论

从 Docker Desktop 迁到 WSL2-only 后，先判断项目是否可以直接在 WSL 内启动。能直接在 WSL 内运行的项目，不需要 PowerShell wrapper。

只有需要保留 Windows PowerShell 作为项目脚本入口时，才评估两条可选桥接路线：

- 方案 C：Windows Docker CLI 通过 Docker context / `DOCKER_HOST` 连接 WSL 内 Docker daemon。
- 方案 D：Windows PowerShell 保留入口，但通过 wrapper 转发到 WSL 内执行 `docker` / `docker compose`。

在“必须保留 Windows PowerShell 入口”的场景里，通常优先试点方案 D。方案 C 技术上可行，但需要额外处理 daemon 暴露、连接配置和 bind mount 路径语义，维护成本通常比看起来高。

## 为什么 Rancher Desktop 不是这条线的核心

Rancher Desktop 有用的场景是替代 Docker Desktop，提供自己的桌面运行时、Moby(dockerd) / containerd、Kubernetes、端口转发和 CLI 集成。它适合作为“方案 B：另一个桌面 Docker 运行环境”。

如果目标是使用用户自己 WSL 发行版里的 Docker Engine，Rancher Desktop 通常帮不上核心问题：

- 它不会把现有 Ubuntu / Debian 发行版里的 `/var/run/docker.sock` 自动变成 Windows Docker Desktop 式体验。
- 它管理的是自己的后端运行环境，而不是给任意 WSL 发行版里的 dockerd 做通用桥接。
- 它不能消除 Windows 项目路径、compose 相对路径、`${DATA_PATH}` 和 bind mount 的语义差异。

因此，在“纯 WSL 内 Docker Engine + 保留 Windows PowerShell 脚本入口”的目标下，不把 Rancher Desktop 作为 C/D 的组成部分。需要 GUI 时优先用 Portainer 管理 WSL 内 dockerd。

## 方案 C：Windows Docker CLI 连接 WSL daemon

### 适用场景

- 仍想在 Windows PowerShell 中直接输入 `docker` / `docker compose`。
- 项目几乎不依赖 Windows 路径 bind mount，或路径已经明确写成 WSL/Linux daemon 能理解的形式。
- 能接受配置 Docker context、`DOCKER_HOST` 或远程 API。

### 连接方式

常见方式有两种：

```powershell
docker context create wsl-docker --docker host=tcp://127.0.0.1:2375
docker context use wsl-docker
docker info
```

或临时指定：

```powershell
$env:DOCKER_HOST = 'tcp://127.0.0.1:2375'
docker info
```

也可以用 SSH context，避免明文 TCP API，但 Windows 到 WSL 的 SSH 用户、密钥和服务维护会更重。

### 主要问题

Docker CLI 连接的是 daemon，而 bind mount 由 daemon 所在主机解释。Windows 侧传入 `C:\repo`、相对路径 `.` 或 `${DATA_PATH}` 时，WSL 内 dockerd 不一定能按 Docker Desktop 的方式自动理解。

高风险场景：

- `docker compose -f docker-compose.yml up` 中有 `.:/workspace`。
- compose 使用 `${DATA_PATH}/postgresql:/var/lib/postgresql`。
- 构建上下文来自 Windows 当前目录。
- 项目脚本依赖 PowerShell 当前目录、临时目录或 Windows-only 路径。

### 判断

方案 C 适合作为轻量连接方案，不适合作为默认迁移答案。只验证 `docker ps` 成功没有意义，至少要验证：

```powershell
docker version
docker compose version
docker compose -f docker-compose.yml config
docker compose -f docker-compose.yml up --no-start
```

有 bind mount 的项目还要启动最小服务，确认容器内真的能读写挂载目录。

## 方案 D：PowerShell wrapper 转发到 WSL 内 Docker CLI

### 适用场景

- 必须让 Windows 项目的 `.ps1`、`pnpm`、`task` 脚本仍从 PowerShell 启动。
- Docker Engine 已安装在 WSL 发行版内。
- 项目依赖 compose、相对路径和 bind mount，但可以通过 wrapper 统一转换路径。

### 推荐形态

Windows 侧提供稳定入口，例如 `docker-wsl.ps1` 或一个 shim `docker` 命令：

```powershell
wsl.exe -d Ubuntu-24.04 -- docker @args
```

本 skill 提供自包含脚本：

```powershell
.\scripts\Invoke-WslDocker.ps1 -Distro Ubuntu-24.04 version
.\scripts\Invoke-WslDocker.ps1 -Distro Ubuntu-24.04 compose -f .\docker-compose.yml config
```

如果要让原来的命令形态直接可用，把 skill 的 `scripts/` 目录放到 PATH 前面，使用同目录的 `docker.ps1` shim：

```powershell
$env:PATH = "C:\path\to\docker-management\scripts;$env:PATH"
docker run --rm alpine:3.20 echo ok
docker compose -f .\docker-compose.yml config
```

本仓库 profile 暂不自动注册 `docker` wrapper。原因是未来也可能选择“项目脚本直接在 WSL 内启动”，自动接管 `docker` 容易形成隐形状态。需要透明命令形态时，优先显式使用 `docker.ps1` shim 或手动调用 `Enable-WslDockerWrapper`。

真正可用的 wrapper 不能只转发参数，还要处理：

- Windows 当前目录转成 WSL 路径，例如 `C:\home\env\powershellScripts` -> `/mnt/c/home/env/powershellScripts`。
- `-f` / `--file` 后面的 compose 文件路径。
- `--project-directory`、build context、env file 路径。
- `${DATA_PATH}` 这类环境变量中的 Windows 路径。
- 工作目录、退出码、stdout / stderr 透传。

### 优点

- 不需要暴露 WSL dockerd TCP API。
- daemon、CLI、compose 插件都在同一个 WSL Linux 环境里，路径语义更一致。
- Windows PowerShell 入口可以保留，现有项目脚本不用一次性全部搬进 WSL。

### 主要问题

- wrapper 需要明确路径转换规则，不能靠隐式猜测。
- 对复杂 compose 项目，仍可能需要逐个项目调整 env 和路径。
- 若脚本大量混用 Windows 工具和 Linux Docker 路径，wrapper 需要先小范围试点。

## 推荐决策

默认记录为：

1. WSL2-only 迁移的长期目标是 WSL 内 Docker Engine + Portainer。
2. wrapper 不是必选项；能直接在 WSL 内启动项目脚本时，不额外接管 Windows PowerShell 的 `docker`。
3. 只有必须保留 Windows PowerShell 入口时，才在方案 C / D 中选桥接方式；此时通常先试点方案 D。
4. 方案 C 保留为备选，仅用于无复杂 bind mount、一次性诊断或明确需要 Windows Docker CLI 的场景。
5. Rancher Desktop 不纳入 C/D；若选择 Rancher Desktop，就把它当成独立方案 B，而不是纯 WSL dockerd 的桥。
6. profile 不自动注册 wrapper；透明 `docker ...` 形态通过显式 PATH shim 或手动启用函数获得。

## 后续验证

wrapper 验证范围至少覆盖：

- Windows PowerShell 中能启动 `docker version` / `docker compose version`。
- compose 文件能被解析。
- bind mount 能在容器内读写。
- `${DATA_PATH}` 分别为 Windows 路径和 WSL 路径时的行为清晰可解释。
- wrapper 能保留 Docker 命令退出码。
