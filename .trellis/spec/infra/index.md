# Infra Integration Guidelines

> 本目录记录仓库内基础设施集成的可执行约定，尤其是本地网关、模型路由、环境变量和跨供应商兼容边界。

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Node/Vitest Scripts](./node-vitest-scripts.md) | 根目录 Vitest 发现的 Node 脚本测试与 shebang 行尾约定 | Active |
| [Test Report Artifacts](./test-report-artifacts.md) | Pester/Vitest 报告统一目录、CI reporter、环境变量覆盖与生成物忽略合同 | Active |
| [PostgreSQL Toolkit](./postgresql-toolkit.md) | PostgreSQL / pgBackRest 命令边界、env 解析和备份范围约定 | Active |
| [Self-Hosted Compose](./self-hosted-compose.md) | 根目录 self-hosted 应用 compose、外部基础设施复用、本机数据盘与 env 忽略契约 | Active |
| [rclone Ops](./rclone-ops.md) | rclone JSON 主配置、WebUI/RC、自动挂载、VFS cache 与日志路径契约 | Active |
| [rathole template](./rathole.md) | rathole 裸二进制、PM2 管理、`.local.toml` 与公网白名单转发模板约定 | Active |
| [Dev Container Templates](./devcontainer-templates.md) | VS Code Dev Container 标准模板、宿主配置挂载与 Agent CLI 复用约定 | Active |
| [Hammerspoon Plugin Contract](./hammerspoon-plugins.md) | macOS Hammerspoon 插件目录、配置合并、部署 manifest 与验证契约 | Active |
| [macOS Finder Quick Actions Contract](./macos-quick-actions.md) | Finder 快捷操作 workflow、Services 安装位置、通用 runner 和 AppleScript quoting 契约 | Active |
| [OpenSSH Server (Windows)](./openssh.md) | Windows OpenSSH Server 模板、Enable-WindowsOpenSsh 启用流程、sshd_config 加固与本机运行态边界 | Active |
| [Package Source Transactions](./package-sources.md) | 跨平台 source 模式、事务、adapter、Stage 0、drift 与恢复合同 | Active |
| [Install Orchestrator](./install-orchestrator.md) | 根安装入口、Stage 1 步骤注册、Preset、失败传播与 source cleanup 合同 | Active |
| [macOS Install Pipeline](./macos-install-pipeline.md) | macOS Stage 0、Core/Full 叶子、桌面集成幂等与 99 验证合同 | Active |
| [Linux/WSL Install Pipeline](./linux-install-pipeline.md) | Ubuntu/Debian 与 WSL Stage 0、Core/Full、Docker、客体配置和 99 验证合同 | Active |
| [Windows Install Pipeline](./windows-install-pipeline.md) | Windows Stage 0、一次 UAC、Core/Full、AutoHotkey、WSL 宿主和 99 验证合同 | Active |
| [Repository Cold Archive](./repository-archive.md) | 根 `archive/` 镜像路径、JSON 索引、归档 CLI、Git 历史与默认质量工具排除合同 | Active |
