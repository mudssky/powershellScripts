# 父任务验收证据（2026-07-25）

父任务 `07-12-remote-provisioning-tool-selection` 的规划 AC 早已勾选；剩余实现 AC 由跨仓子任务落地后回填。

## 子任务 / 兄弟任务

| 仓库 | 任务 | 状态 |
|---|---|---|
| `powershellScripts` | `07-12-windows-psrp-bootstrap` | 已归档（2026-07-12） |
| `powershellScripts` | `07-12-ansible-managed-host-preparation` | 已归档（2026-07-25） |
| `self-hosted-compose` | `07-12-ansible-remote-provisioning` | 已归档（2026-07） |

## Secrets

- 路径：`/Volumes/Data/projects/forgejo/powershellScripts-secrets`
- Remote：`ssh://git@macmini:32222/mudssky/powershellScripts-secrets.git`
- 未认证访问 Forgejo API/页面返回 404（Private 预期）
- 已跟踪内容无 SSH 私钥；仅 `public_keys/*.pub` 与凭据脚本/测试

## Ansible 基线（本机复核）

控制面：`/Volumes/Data/projects/forgejo/self-hosted-compose/deployments/ansible`

- `ansible-inventory -i inventories/homelab --list`：linux / darwin / windows 分组可用
- syntax-check：`powershell-scripts-bootstrap|provision|verify.yml` 通过
- 连接：`ansible -i inventories/homelab macmini -m ping` → `pong`
- submodule：`reference/powershellScripts` → GitHub URL，gitlink `67cc93d…`

## Core / WhatIf 状态快照

| 主机 | 平台 | phase | status | exitCode | 说明 |
|---|---|---|---|---|---|
| `iminipro820` | windows | verify | Succeeded | 0 | Core 结构化验证通过 |
| `iminipro820-wsl` | linux | provision | Blocked | 10 | Core WhatIf 预览 verify 漂移（合同预期） |
| `macmini` | darwin | provision | Blocked | 10 | 同上 |

Windows PSRP bootstrap / `win_ping` / 重启恢复细节见 compose 归档 PRD/implement，不在此重复展开。
