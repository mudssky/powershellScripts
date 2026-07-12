# Windows PSRP 远程 bootstrap

## Goal

提供一个 Windows PowerShell 5.1 兼容、要求当前进程已是管理员且不触发 UAC 的远程 PSRP
bootstrap，使 Ansible 能先通过现有 OpenSSH 执行固定脚本，再通过仅绑定 Tailscale IPv4 的
HTTPS listener 使用 PSRP 管理目标机。

## Requirements

- 自动发现或显式接收唯一的 Tailscale IPv4，并拒绝 LAN、loopback、wildcard 或歧义地址。
- 创建或复用带固定 subject 前缀的本机自签名证书，HTTPS listener 只绑定该 Tailscale IP 和端口 `5986`。
- 保持 WinRM `AllowUnencrypted=false`，启用 NTLM 所需的 Negotiate authentication。
- 不改变 Windows 防火墙 profile 的全局启用状态；启用时创建 local-address 与 CGNAT remote-address scoped rule，关闭时只验证 listener。
- 不安装、停止、重配或删除 OpenSSH，不修改其端口和授权文件。
- 支持 `-WhatIf`、Text/Json 单文档结果、幂等重跑和显式 `-Rollback`。
- rollback 只删除本脚本管理的 listener、规则和证书，不碰非托管 PSRP/SSH 资源。
- 所有函数包含中文帮助、参数和返回值说明。

## Acceptance Criteria

- [x] Pester 覆盖 Tailscale IP 选择、listener 计划、证书复用、防火墙启用/关闭、幂等和 rollback 计划。
- [x] Windows PowerShell 5.1 parser 可加载脚本和模块。
- [x] `-WhatIf -OutputFormat Json` 不产生系统写操作，并返回可解析单文档。
- [x] 非管理员实际执行返回 Blocked/10，不请求 UAC。
- [x] `pnpm qa`、`pnpm test:pwsh:all` 和 `git diff --check` 通过。

## Notes

- 父规划：`.trellis/tasks/07-12-remote-provisioning-tool-selection/`。
- Windows 实机 apply 由后续 Ansible 任务在用户指定单机上执行，本子任务只落公共脚本、测试和文档。
