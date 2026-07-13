# WSL SSH 宿主与客体入口

## Goal

提供可跨 Windows 11 + WSL2 主机复用的 SSH 管理入口原语：WSL guest 负责 key-only sshd，Windows host 负责稳定端口转发、开机恢复、firewall scoped rule 和 rollback，供外部 Ansible 控制面以固定参数调用。

## Background

- 现有 `windows/wsl/Initialize-WslHost.ps1` 只管理 WSL capability、distribution 和 `.wslconfig`。
- 现有 `linux/wsl/wsl.conf` 与 Linux pipeline 管理 WSL 客体 systemd/Docker，但 managed-host preparation 明确对 WSL SSH 返回 Blocked。
- 新入口必须保持 Windows 宿主与 WSL 客体职责分离，不改变 Windows OpenSSH、PSRP、Tailscale 或 firewall profile。

## Requirements

- `linux/wsl/` 提供 guest plan/apply/verify/rollback：Ubuntu/Debian、openssh-server、sshd drop-in、authorized key marker、systemd enable/start。
- `windows/wsl/` 提供 host plan/apply/verify/rollback：固定 distribution/user/ports、runtime helper、S4U Highest AtStartup task、动态 WSL IPv4、portproxy 和 firewall rule。
- Windows orchestrator 只调用仓库内固定 guest helper，不接受任意 shell；参数只允许合法 distribution/user/port/public key。
- 默认 SSH 策略为 `PasswordAuthentication no`、`PermitRootLogin no`、`PubkeyAuthentication yes`。
- Windows listener 可以是 `0.0.0.0:2222`，firewall remote allowlist 支持 `LocalSubnet` 与 `100.64.0.0/10`；不改变 profile 启停状态。
- 所有入口支持 Preview/Apply/Verify/Rollback、单文档 JSON、幂等和精确 managed-resource rollback。
- runtime 状态不得包含公钥正文、密码、private key 或任意 credential。

## Acceptance Criteria

- [ ] Preview 零写入并输出完整 host/guest 计划。
- [ ] guest apply 第二次 unchanged，sshd key-only、systemd active/enabled，authorized key marker 不删除其他 key。
- [ ] host apply 第二次 unchanged，scheduled task/portproxy/firewall 只管理本功能命名资源。
- [ ] WSL IP 变化后 runtime helper 精确刷新 portproxy。
- [ ] rollback 不卸载 openssh-server，不删除其他 key/task/rule/portproxy，也不修改 Windows OpenSSH/PSRP/Tailscale/firewall profile。
- [ ] Pester/Bash tests、`pnpm qa`、`pnpm test:pwsh:all` 和 `git diff --check` 通过。

## Out of Scope

- host-specific inventory、secret/public-key repository 解析和 Ansible apply guard。
- mirrored networking、WSL 内 Tailscale、router port forward、Windows 自动登录或保存 PIN。
- 安装/迁移 WSL distribution 或部署业务服务。
