# 实施计划

## 0. 多仓库前置与任务边界

1. 当前任务作为跨仓库父规划，实施前分别在 `powershellScripts` 与 `self-hosted-compose` 创建/激活对应 Trellis 实施任务。
2. `powershellScripts` 子任务拥有公共远程入口、平台脚本与测试。
3. `self-hosted-compose` 子任务拥有 submodule、Ansible control plane、inventory 和文档。
4. `powershellScripts-secrets` 只初始化仓库结构与说明，不与任一父仓库混合提交。
5. 每个仓库分别执行 `git status`、验证和 Conventional Commit。

## 1. 固定 GitHub 权威版本

- [x] 确认 `powershellScripts` 当前计划纳入 submodule 的 commit 仅包含文档，无需运行 QA。
- [x] 提交当前任务规划/公共代码变更，并推送到 GitHub `master`。
- [x] 用 `git ls-remote` 验证 GitHub 包含目标 commit。
- [x] 不依赖 Forgejo pull mirror 是否已同步。

风险点：当前本地 `master` 已领先 GitHub，不能在目标 commit 尚未推送时创建父仓库 gitlink。

## 2. 配置 self-hosted-compose submodule

- [x] 在 `self-hosted-compose` 创建独立 Trellis 实施任务并读取其 infra/backend specs。
- [x] 确认父仓库工作树干净。
- [x] 添加 GitHub submodule 到 `reference/powershellScripts`。
- [x] 检查 `.gitmodules` 仅包含公开 GitHub URL和相对路径，不含本机绝对路径或私有 Forgejo URL。
- [x] 在根 `package.json` 增加：
  - `submodules:status`
  - `submodules:update`
  - `submodules:pull`
- [x] 在 `biome.json` 和 `.prettierignore` 排除整个 submodule 路径。
- [x] 在 README/AGENTS 记录初始化、更新、dirty 状态、父子提交顺序和只读依赖边界。
- [x] 不修改 `pnpm-workspace.yaml`，不复制完整 submodule-host 模板，不启用递归 push。

验证：

```bash
git submodule status
pnpm submodules:status
pnpm submodules:update
pnpm lint
pnpm test
pnpm check
git diff --check
```

额外验证：临时 fresh clone 或 deinit/init 后，`git submodule update --init --recursive` 能从 GitHub 获取固定 commit。

## 3. 初始化私有 secrets 仓库

- [ ] 通过 macmini Forgejo 用户命名空间创建 `powershellScripts-secrets`，明确验证仓库为 Private。
- [ ] 本地 checkout 位于 `/Volumes/Data/projects/forgejo/powershellScripts-secrets`。
- [ ] 增加中文 README、安全边界、恢复流程、凭据轮换触发条件和最小目录结构。
- [ ] 不加入 SSH 私钥；只保存公钥/授权声明和用户确认允许的管理员密码、Token。
- [ ] 禁用或不配置公开 mirror、公共 webhook 和不必要的 CI 日志输出。
- [ ] 首次 commit/push 后用 Forgejo UI/API 和 `git remote -v` 验证私有远端与本地路径。

## 4. 扩展 Ansible control plane

- [ ] 锁定 Ansible collections 和 Python 依赖，确保 Linux/macOS/WSL2 一致。
- [ ] 扩展 homelab inventory 的 Linux、darwin、windows 分组和 host vars。
- [ ] 增加 secrets checkout 解析与缺失阻断，不提交绝对路径。
- [ ] 增加 workstation bootstrap/provision/verify playbooks。
- [ ] 默认 `provision_apply=false`，真实执行必须显式 `--limit` 和 apply 开关。
- [ ] role 从 `reference/powershellScripts` 读取固定版本的入口与合同，不复制包清单。
- [ ] 输出每台主机的阶段状态、退出码、重启要求和精确重跑命令。

验证：

```bash
cd deployments/ansible
ansible-galaxy collection install -r requirements.yml
ansible-inventory --list --yaml
ansible-playbook --syntax-check playbooks/workstation-bootstrap.yml
ansible-playbook --syntax-check playbooks/workstation-provision.yml
ansible-playbook --syntax-check playbooks/workstation-verify.yml
```

## 5. Windows OpenSSH 到 PSRP bootstrap

- [ ] 在 `powershellScripts` 提供 Windows PowerShell 5.1 兼容、无 UAC 交互的固定 bootstrap 入口。
- [ ] 发现并校验当前 Tailscale IPv4。
- [ ] 创建/更新自签名证书和仅绑定该 IP 的 HTTPS listener `5986`。
- [ ] 保持 `AllowUnencrypted=false`，使用 NTLM 和强制 message encryption。
- [ ] 保留 Windows 防火墙全局状态；启用时添加 scoped rule，关闭时只验证监听地址。
- [ ] 不修改现有 OpenSSH listener、端口、服务和授权配置。
- [ ] Ansible 通过 SSH 执行 bootstrap 后，切换 PSRP 并运行 `win_ping`。
- [ ] 绑定、证书或 PSRP 验证失败时仍可通过 SSH 回滚/重试。

测试与验证：

- Pester 覆盖 Tailscale IP 选择、listener 计划、证书重用、防火墙状态分支、幂等性和 rollback 计划。
- `pnpm test:pwsh:all`。
- `pnpm qa`。
- Windows 实机先 DryRun/计划，再单机 bootstrap 和端口监听验证。

## 6. 三平台 Core 编排

- [ ] Linux/macOS 使用 SSH，Windows 正式阶段使用 PSRP。
- [ ] 管理员机器阶段与普通用户 Stage 1 分离。
- [ ] clone/更新公开 GitHub `powershellScripts`，版本来自父仓库 submodule gitlink。
- [ ] 首期执行 `Core`；`Full` 仅显式 opt-in，不纳入完全无人值守验收。
- [ ] 重启使用平台安全边界：Windows `win_reboot`，Linux/macOS 不擅自重启。
- [ ] 调用平台 `99` 验证入口并解析 JSON。
- [ ] 第二次运行验证幂等，仅处理缺失或 drift。

## 7. 最终质量门

- [ ] `powershellScripts`: `pnpm qa`。
- [ ] 涉及 pwsh：`pnpm test:pwsh:all`。
- [ ] `self-hosted-compose`: `pnpm check`。
- [ ] 两个父/子仓库分别 `git status --short`。
- [ ] `self-hosted-compose`: `git submodule status` 指向 GitHub 已存在 commit，submodule 工作树干净。
- [ ] secrets 仓库：remote、private visibility、无 SSH 私钥、无意外生成物。
- [ ] Ansible syntax/inventory 检查通过。
- [ ] Linux/macOS/Windows 至少完成连接与 `Core` WhatIf；真实 apply 按用户确认的单机范围执行。

## 8. 提交顺序

1. `powershellScripts` 公共入口与测试 commit，推送 GitHub。
2. `powershellScripts-secrets` 初始化 commit，推送私有 Forgejo。
3. `self-hosted-compose` submodule gitlink、工程规范和 Ansible commit，推送私有 Forgejo。
4. 若后续修改子仓库，始终先提交/推送子仓库，再更新父仓库 gitlink。
