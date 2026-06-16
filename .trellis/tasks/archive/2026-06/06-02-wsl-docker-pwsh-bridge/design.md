# Design: WSL Docker PowerShell Bridge

## 边界

本阶段先记录 Windows PowerShell 调用 WSL 内 Docker Engine 的方案边界，不把诊断脚本或 wrapper 作为已确定交付物。核心目标是把方案 C / D 的取舍写进 `docker-management` skill，避免后续把“能连 daemon”误写成“Windows 项目脚本完全兼容”。

## 方案 C：Windows CLI 远程连接 WSL daemon

Windows 侧保留 Docker CLI，通过 Docker context、`DOCKER_HOST=tcp://...` 或 SSH context 连接 WSL 内 dockerd。

优点：

- Windows 侧命令形态最接近 Docker Desktop。
- 对不依赖 bind mount 的命令足够简单。

缺点：

- 需要配置 TCP / SSH 连接和安全边界。
- bind mount 由 WSL daemon 解释，Windows 路径不会天然获得 Docker Desktop 式转换。
- `docker ps` 成功不能证明 compose 项目可启动。

## 方案 D：PowerShell wrapper 转发到 WSL CLI

在必须保留 Windows 侧脚本入口时，wrapper 调用：

```powershell
wsl.exe -d <distro> -- docker <args>
```

本轮实现两层入口：

- skill 自包含脚本：`ai/skills/dev/docker-management/scripts/Invoke-WslDocker.ps1`，供安装态 skill 或手动调用使用。
- skill 透明 shim：`ai/skills/dev/docker-management/scripts/docker.ps1`，放到 PATH 前面后保留 `docker run ...` / `docker compose ...` 原命令形态。
- psutils 手动入口：`Enable-WslDockerWrapper`，需要时由用户显式调用；profile 暂不自动注册。

优点：

- 不需要暴露 Docker daemon TCP API。
- Docker CLI、compose 插件和 daemon 都在 WSL 内，路径语义更统一。
- Windows PowerShell 入口仍可按需保留，降低迁移对项目脚本的冲击。

缺点：

- wrapper 必须显式转换当前目录、compose 文件、env file、build context 和 `${DATA_PATH}`。
- 复杂项目仍需要逐项验证 bind mount。
- 混用 Windows 工具链和 Linux Docker 路径时，需要定义清晰边界。

## Rancher Desktop 边界

Rancher Desktop 是独立桌面运行时，适合作为 Docker Desktop 替代方案。它不作为方案 C / D 的组成部分，因为它不会把用户已有 WSL 发行版里的 dockerd 自动桥接成 Docker Desktop 式 Windows 路径体验。

## 文档集成

- 新增 `references/wsl-powershell-bridge.md` 记录 C/D。
- `SKILL.md` 主题入口指向该专题。
- `references/platforms/windows.md` 的 Docker Desktop → WSL2-CLI 迁移步骤加入 C/D 选择。
- `references/commands.md` 保留最小验证命令，并指向 `Invoke-WslDocker.ps1`。
