# 三平台远程装机与 Ansible 集成

## Goal

复用 `powershellScripts` 现有跨平台 Stage 0/Stage 1 安装流水线，为不超过 10 台 Linux、macOS、Windows 个人设备或服务器建立可手动触发、可验证、可重跑的远程装机与持续配置能力，同时保持公开代码、私人基础设施和明文凭据的仓库边界清晰。

## Background

- `powershellScripts` 已有 Linux、macOS、Windows 平台入口；Stage 0 负责 Git、包管理器与 PowerShell 7，根 `install.ps1` 负责 Stage 1。
- Ansible 与 pyinfra 都要求目标机先具备网络和远程执行通道，不能单独完成尚无操作系统或网络的裸机安装。
- pyinfra 的 Windows 目标机支持依赖当前明确标注为不适合生产的独立插件；Ansible 具有成熟 inventory、collections、Windows PSRP 和重启恢复能力。
- `self-hosted-compose/deployments/ansible` 已存在 Linux、macOS、Windows inventory 分组、roles/playbooks 结构和 `ansible.windows` 依赖，应作为唯一 Ansible control plane。
- `windows/00quickstart.ps1` 当前通过 UAC 完成机器级安装并拒绝管理员进程直接执行，不能原样用作远程无交互入口。

## Requirements

### R1 工具与装机边界

- 选择 Ansible，正式支持 Linux、macOS、Windows 三平台混合管理。
- 首次系统安装、网络接入和最初远程管理员通道属于前置 bootstrap；PXE、WinPE、`Autounattend.xml`、云实例创建不进入 MVP。
- 远程编排只负责 inventory、连接、Stage 0/Stage 1 调用、重启恢复和结果汇总，不复制平台包清单或步骤图。
- 仅当未来范围缩小为少量 Unix-like 主机、明确偏好 Python DSL 且不需要正式 Windows 管理时，才重新评估 pyinfra。

### R2 仓库与 Submodule 边界

- GitHub `https://github.com/mudssky/powershellScripts.git` 是 `powershellScripts` 唯一权威源，不配置 GitHub/Forgejo 双 push。
- 现有 Forgejo pull mirror 仅作为周期性备份，不参与 Ansible 版本选择或 submodule 解析。
- `self-hosted-compose` 在 `reference/powershellScripts` 以 GitHub URL 引入 submodule，并固定到 GitHub 已存在的 commit，供 Ansible 和 agent 同时读取两个仓库代码。
- 子仓库源码由 `powershellScripts` 独立验证、提交并推送 GitHub；父仓库只提交 `.gitmodules`、gitlink、submodule 管理脚本、文档和 QA 排除。
- submodule 不加入 `pnpm-workspace.yaml`；父仓库 Biome、Prettier、lint、test 不得递归处理子仓库。
- 父仓库提供 `submodules:status`、`submodules:update`、`submodules:pull`，不提供递归 push。

### R3 控制端、Inventory 与 Secrets

- 第一阶段不超过 10 台设备，使用静态 YAML inventory，不引入 CMDB、云动态 inventory 或 Tailscale API inventory。
- Linux/macOS 原生运行 Ansible；Windows 控制端通过 WSL2 Ubuntu；支持经 VS Code Remote SSH 在 Linux 上手动执行。
- MVP 不包含常驻控制器、定时巡检、CI runner 或无人值守调度。
- 本次创建 Forgejo 用户私有仓库 `powershellScripts-secrets`，本地 checkout 为 `/Volumes/Data/projects/forgejo/powershellScripts-secrets`。
- secrets 仓库直接保存用户确认允许的管理员密码和 Token，不使用 Ansible Vault；仓库必须保持 Private，仅经 Tailscale/可信网络访问。
- secrets 仓库不保存 SSH 私钥。每台控制端独立保管私钥，仓库只保存公钥与授权声明。
- 私有 secrets 仓库不作为 submodule；主仓库通过环境变量或忽略的本地配置解析 checkout 路径，不提交绝对路径或私有 URL。
- 明文凭据会进入 Forgejo Git 历史、每个 clone 和 Restic 备份；仓库误公开、Forgejo/控制端疑似入侵或旧机器退役时必须轮换相关凭据。

### R4 Windows OpenSSH 到 PSRP Bootstrap

- Windows 前置条件为：系统已安装、Tailscale 已连接、管理员 OpenSSH 可登录。
- Ansible 通过 OpenSSH 下发 Windows PowerShell 5.1 兼容的固定 bootstrap，再切换到 PSRP 正式管理。
- PSRP 使用 HTTPS + NTLM，强制 message encryption，保持 `AllowUnencrypted=false`。
- HTTPS listener 使用端口 `5986`，只绑定当前 Tailscale IP，不使用 `Address='*'`。
- bootstrap 不改变 Windows 防火墙全局启用/关闭状态；防火墙启用时添加 Tailscale scoped rule，关闭时验证 `5986` 未监听 LAN/Wi-Fi 地址。
- 现有 OpenSSH listener、端口、服务和授权配置保持不变，PSRP 失败时 SSH 仍是恢复通道。
- Windows 管理员机器阶段与普通用户 Stage 1 显式分离，不依赖可见桌面、UAC 点击或交互式登录。
- 机器阶段完成后按需使用 `win_reboot`，等待 PSRP 恢复，再执行用户阶段与 JSON 验证。

### R5 Provisioning 与安全执行

- Linux/macOS 使用 SSH，Windows 正式阶段使用 PSRP。
- 三平台 `Core` 是首期强验收范围；`Full` 允许显式调用，但桌面权限、GUI、AutoHotkey、WSL、Hammerspoon 和登录项不承诺完全无人值守。
- Ansible 默认只做连接检查、计划和 `WhatIf`；真实 apply 必须显式指定 `--limit` 和 apply 开关。
- 平台退出码 `1`、`2`、`10` 必须保留语义；`10` 需区分 RestartRequired 与外部 Blocked，并输出精确重跑命令。
- 完成后调用平台 `99` 验证入口，解析结构化结果；第二次执行应跳过已满足状态，仅处理缺失或 drift。

## Acceptance Criteria

- [x] 以官方资料完成 Ansible/pyinfra 能力、Windows 支持和首次引导边界比较，并选择 Ansible。
- [x] 确定控制端矩阵、静态 inventory 规模、三平台 `Core` 范围和手动执行方式。
- [x] 确定 Windows OpenSSH → PSRP、管理员/用户阶段、重启恢复和 Tailscale-only listener 设计。
- [x] 确定 GitHub 权威源、`self-hosted-compose` submodule、私有 secrets 仓库和父子 Git 边界。
- [x] `design.md` 描述架构、数据流、安全边界、失败语义和 rollback。
- [x] `implement.md` 描述跨仓库顺序、验证命令、风险点和提交顺序。
- [x] 用户审核并批准最终 PRD、design 和 implement。
- [x] GitHub 中存在父仓库要固定的 `powershellScripts` commit。
- [x] `self-hosted-compose/reference/powershellScripts` 以 GitHub URL 初始化为 submodule，父仓库 QA 不递归修改子仓库。
- [ ] Forgejo `powershellScripts-secrets` 已创建、初始化并验证为 Private，且不包含 SSH 私钥。
- [ ] Ansible inventory、syntax-check 和连接基线通过。
- [ ] Windows 可从管理员 OpenSSH 完成 PSRP bootstrap、`win_ping`、重启恢复和监听地址验证。
- [ ] Linux、macOS、Windows 均完成 `Core` 计划/`WhatIf` 和结构化验证；真实 apply 仅在用户批准的主机上执行。
- [ ] `powershellScripts` 的 `pnpm qa` 与 `pnpm test:pwsh:all` 通过；`self-hosted-compose` 的 `pnpm check` 通过。

## Out of Scope

- PXE、WinPE、无人值守系统镜像安装、云厂商实例创建。
- 动态 inventory、常驻 runner、定时执行和自动巡检。
- 把 `Full` 桌面流程纳入首期完全无人值守验收。
- 把 secrets 仓库或 Forgejo mirror 用作 `powershellScripts` submodule 来源。
- GitHub/Forgejo 双 push、Forgejo → GitHub force push mirror。
- 把父仓库格式化、测试或提交规则强加到独立子仓库。

## Open Questions

无。等待用户审核最终规划产物。
