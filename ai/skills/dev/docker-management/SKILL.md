---
name: docker-management
description: 管理 Docker 运行方案的选型、配置、迁移与日常运维。Use when 用户要选择/对比 Docker 运行方案（Docker Desktop / Rancher Desktop / WSL2 纯 CLI）、配置 WSL2+Docker Engine+Portainer、从 Docker Desktop 迁移、决定是否备份镜像与数据卷、做容器日常运维（资源限制/日志/端口安全绑定/清理/代理）或排查 Docker 故障。
---

# Docker 管理

## 使用时机

用于帮助 agent 与用户选择 Docker 运行方案、配置 Windows 下的 Docker 运行环境、迁移 Docker Desktop 工作负载，以及处理日常运维和排障。

不要把本 skill 当成 Docker 入门教程。用户不熟悉容器基础概念时，先解释必要背景，再进入选型、配置或迁移。

## 第一步：确定平台

| 平台 | 状态 | 入口 |
|---|---|---|
| Windows | 本期已覆盖 | `references/platforms/windows.md` |
| macOS | 待补充 | 规划入口：`references/platforms/macos.md` |
| Linux | 待补充 | 规划入口：`references/platforms/linux.md` |

当前只有 Windows 平台内容完整。macOS / Linux 任务只引用跨平台主题文件，遇到平台安装、卸载或迁移步骤时先查官方文档。

## 第二步：按主题读取

- 选型对比：读 `references/runtime-options.md`。
- Windows 安装、方案 C 配置、Docker Desktop 迁移：读 `references/platforms/windows.md`。
- WSL2 `.wslconfig` / `/etc/wsl.conf` 模板：读 `references/wsl2-config-templates.md`。
- WSL2 mirrored / NAT 网络代理、Docker daemon 拉取代理排障：读 `references/wsl-network-proxy.md`。
- Windows PowerShell 调用 WSL 内 Docker Engine 的 C/D 方案取舍：读 `references/wsl-powershell-bridge.md`。
- 迁移策略、要不要备份、备份/恢复命令：读 `references/migration-strategy.md`。
- 日常运维：读 `references/daily-ops.md`。
- 命令与 compose 工作流：读 `references/commands.md`。
- 故障排查：读 `references/troubleshooting.md`。

## 可复用脚本

- WSL2 Docker 代理诊断：优先运行 `scripts/Test-WslDockerProxy.ps1`，再根据输出决定是否修改 daemon proxy、代理软件监听或防火墙。
- 可选 Windows PowerShell wrapper：仅在需要保留 Windows 侧项目脚本入口时，方案 D 可用 `scripts/Invoke-WslDocker.ps1` 转发到 WSL 内 `docker` / `docker compose`；能直接在 WSL 内启动的项目不需要启用 wrapper。

## 安全护栏

迁移、卸载 Docker Desktop、删除容器、清理卷、执行 `prune`、注销 WSL 发行版、覆盖 `.wslconfig` / `/etc/wsl.conf` 都是高风险操作。执行前先确认：

- 是否已经按 `references/migration-strategy.md` 判断并完成必要备份。
- 目标运行时是否已经可用，并能拉取镜像、启动容器、访问端口。
- 数据库、对象存储、消息队列等有状态服务是否已经停写并恢复演练。
- 破坏性命令是否明确列出影响范围和回滚方式。
