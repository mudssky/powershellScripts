# Docker 运行方案选型

## 目录

- [三方案快速对比](#三方案快速对比)
- [平台扩展矩阵](#平台扩展矩阵)
- [怎么选](#怎么选)
- [方案说明](#方案说明)

## 三方案快速对比

| 方案 | Windows 状态 | macOS 状态 | Linux 状态 | 运行引擎 | GUI | 适合人群 |
|---|---|---|---|---|---|---|
| Docker Desktop | 成熟方案 | 待补充 | 待补充 | Docker Desktop 内置 Docker Engine / VM | 有 | 希望官方集成、低维护成本、接受授权条款的团队 |
| Rancher Desktop | 可替代 Docker Desktop | 待补充 | 待补充 | Moby(dockerd) 或 containerd | 有 | 希望开源桌面运行时、需要 Kubernetes 或 nerdctl 的用户 |
| WSL2-CLI + Portainer | 本期推荐的轻量纯 CLI 方案 | 不适用 | 待补充为原生 Engine 路径 | WSL2 内 Docker Engine | Portainer WebUI | 熟悉 Linux、希望控制资源/网络/代理细节、可接受命令行维护的用户 |

## 平台扩展矩阵

| 维度 | Docker Desktop | Rancher Desktop | WSL2-CLI + Portainer |
|---|---|---|---|
| Windows | 官方桌面方案，集成 WSL2 后端；商用授权需按 Docker 条款判断 | 开源桌面替代方案，可选 Moby 或 containerd | 在用户发行版内直接运行 Docker Engine，Portainer 提供 WebUI |
| macOS | 待补充 | 待补充 | 不适用；后续用原生 Docker Engine/虚拟化替代方案描述 |
| Linux | 待补充 | 待补充 | 后续扩展为原生 Docker Engine + Portainer |
| 资源控制 | GUI 内配置，Windows 下仍受 WSL/VM 资源影响 | GUI 内配置 VM 资源 | `%UserProfile%\.wslconfig` 控制 WSL2 VM，容器再用 `--memory` / `--cpus` |
| 网络模型 | Windows 侧由 Docker Desktop 管理端口转发 | Windows 侧由 Rancher Desktop 管理端口转发 | WSL mirrored/NAT + Docker 端口绑定；默认本机开发建议绑定 `127.0.0.1` |
| k8s | 可选启用 | 一等能力 | 不内置；需要时另行安装 k3d/kind/minikube |
| 迁移复杂度 | 源方案 | 中等，需要切换 CLI 上下文并恢复数据 | 较高，需要安装 Engine、配置 systemd、恢复卷和 compose |

## 怎么选

1. 要最低维护成本、官方文档和 UI 集成优先：选 Docker Desktop，并确认授权条款符合团队使用场景。
2. 要桌面 GUI、Kubernetes、一套开源替代方案：选 Rancher Desktop。需要 Docker CLI 兼容时优先选 Moby(dockerd) 引擎；偏 Kubernetes / nerdctl 工作流时再考虑 containerd。
3. 要最轻、最可控、以 CLI 为主：选 WSL2-CLI + Portainer。这个方案把 Docker Engine 放在 WSL2 发行版内，适合本机开发数据库、compose 栈和可重复的 Linux 运维习惯。
4. 有不可再生数据时，先做迁移决策和备份，不要先卸载旧运行时。

## 方案说明

### Docker Desktop

优点是官方集成完整、安装和升级简单、文档与生态最常见；缺点是资源占用和授权条款需要评估。Windows 迁出步骤见 `platforms/windows.md`。

### Rancher Desktop

优点是开源、可同时覆盖容器和 Kubernetes，本期 Windows 迁移目标建议使用 Moby(dockerd) 以保持 Docker CLI / compose 兼容；缺点是与 Docker Desktop 的数据卷、上下文和网络行为不同，需要迁移验证。

Rancher Desktop 是独立桌面运行时，不是把 Windows PowerShell 桥接到用户已有 WSL 发行版内 dockerd 的通用工具。如果目标是纯 WSL2 Docker Engine，按 `wsl-powershell-bridge.md` 在方案 C / D 中选择。

### WSL2-CLI + Portainer

优点是透明、轻量、可按 Linux 运维方式管理 Docker Engine；缺点是安装、systemd、代理、日志和资源限制都要自己维护。完整配置见 `platforms/windows.md` 的方案 C。如果必须从 Windows PowerShell 调用 WSL 内 Docker Engine，wrapper 转发是可选入口之一；能在 WSL 内直接启动项目脚本时，不需要额外启用 wrapper。
