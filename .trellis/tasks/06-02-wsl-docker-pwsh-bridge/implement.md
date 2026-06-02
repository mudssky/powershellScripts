# Implement: WSL Docker PowerShell Bridge

## 步骤

- [x] 新增 `references/wsl-powershell-bridge.md`，记录方案 C / D 和 Rancher Desktop 边界。
- [x] 新增 `ai/skills/dev/docker-management/scripts/Invoke-WslDocker.ps1`，作为 skill 自包含 wrapper。
- [x] 新增 `ai/skills/dev/docker-management/scripts/docker.ps1`，作为 PATH shim 支持原始 `docker ...` 命令形态。
- [x] 扩展 `psutils/modules/docker.psm1`，提供 WSL Docker wrapper 检测、路径转换和启用函数。
- [x] 暂不在 Windows profile 自动启用 `docker` wrapper，仅保留显式启用能力。
- [x] 更新 `SKILL.md`，把 PowerShell 调用 WSL Docker Engine 的方案判断列入主题入口。
- [x] 更新 `references/platforms/windows.md`，在 Docker Desktop → WSL2-CLI 迁移步骤中记录 C/D 选择。
- [x] 更新 `references/commands.md`，保留最小验证命令并指向 wrapper。
- [ ] 运行格式检查、Pester 测试和根目录 QA。

## 回滚点

- 文档改动集中在 docker-management skill，回滚不影响现有运行脚本。
- 若后续保留早先草稿脚本，需要单独复核脚本契约和测试范围。
