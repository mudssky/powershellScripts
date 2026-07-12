# 远程装机与多仓库集成设计

## 1. 架构边界

方案由三个独立 Git 仓库组成：

| 仓库 | 权威来源 | 职责 |
|---|---|---|
| `powershellScripts` | GitHub 公开仓库 | 跨平台 Stage 0/Stage 1、远程安全入口、平台验证与公共文档 |
| `self-hosted-compose` | macmini Forgejo 私有仓库 | Ansible control plane、inventory、主机差异、连接 bootstrap、执行编排与状态汇总 |
| `powershellScripts-secrets` | macmini Forgejo 用户私有仓库 | 明文管理员密码、Token 等实际凭据；不保存 SSH 私钥 |

GitHub 是 `powershellScripts` 的唯一权威源。现有 Forgejo pull mirror 只保留为周期性备份，不参与发布、Ansible 版本选择或 submodule URL 解析。

## 2. Submodule 设计

`self-hosted-compose` 在以下路径引入公开 GitHub 仓库：

```text
reference/powershellScripts
```

`.gitmodules` 使用公开 URL：

```text
https://github.com/mudssky/powershellScripts.git
```

父仓库固定一个 GitHub 已存在的 commit。submodule 主要用于：

- agent 在 `self-hosted-compose` 工作区内同时读取安装编排和平台脚本。
- Ansible role 在控制端读取固定版本的公共脚本、入口和验证合同。
- 父仓库通过 gitlink 明确记录本次运维代码依赖的 `powershellScripts` 版本。

父仓库不拥有子仓库源码。对子仓库的修改必须先在 `powershellScripts` 独立验证、提交并推送 GitHub，再在父仓库更新 gitlink。

### 工程规范适配

沿用 `self-hosted-compose` 既有 pnpm workspace、Biome、Prettier、Husky 和 Trellis 配置，不复制 `project-standards` 的完整 submodule-host 模板。

只补以下缺口：

- 根 `package.json` 增加 `submodules:status`、`submodules:update`、`submodules:pull`。
- `biome.json` 和 `.prettierignore` 排除 `reference/powershellScripts`。
- 根 README/AGENTS 记录父子仓库边界、初始化、更新和提交顺序。
- 不把 submodule 纳入 `pnpm-workspace.yaml` 的 `apps/*`。
- 首版不修改 `.trellis/config.yaml` 的 package 模式，避免把现有 single-repo spec 层级意外切换为 monorepo package scope。
- 不增加 `submodules:push`：父仓库将子模块视为 GitHub 上的只读依赖，不能从父仓库递归推送子仓库提交。

## 3. Ansible Control Plane

复用 `self-hosted-compose/deployments/ansible`，不在公开仓库复制第二套 inventory 和 Ansible 配置。

目录扩展方向：

```text
deployments/ansible/
├── inventories/homelab/
├── playbooks/
│   ├── workstation-bootstrap.yml
│   ├── workstation-provision.yml
│   └── workstation-verify.yml
└── roles/
    ├── workstation_common/
    ├── powershell_scripts/
    └── windows_psrp_bootstrap/
```

职责：

- inventory 保存主机名、平台分组、Tailscale 地址、目标用户和非敏感策略。
- secrets 仓库提供实际密码和 Token，通过控制端本地路径加载。
- role 读取 submodule 中的安装入口与脚本，不复制包清单或平台步骤图。
- 默认只执行连接检查、计划和 `WhatIf`；真实安装必须显式指定 `--limit` 与 apply 开关。

## 4. 控制端矩阵

| 控制端 | 运行方式 |
|---|---|
| Linux | 原生 Python/Ansible；支持通过 VS Code Remote SSH 手动执行 |
| macOS | 原生 Python/Ansible |
| Windows | WSL2 Ubuntu 内运行，不支持原生 Windows control node |

所有控制端 clone `self-hosted-compose` 并初始化公开 submodule；需要真实执行时再 clone 私有 secrets 仓库到约定的本地路径。

## 5. 被控端流程

### Linux/macOS

1. 使用 SSH 连接。
2. 验证平台、架构、sudo 和 Tailscale 基线。
3. clone/更新公开 `powershellScripts` 到目标用户目录。
4. 调用现有平台 Stage 0/Stage 1。
5. 首期以 `Core` 为强验收；`Full` 为显式可选。
6. 调用平台 `99` 验证入口并收集结构化结果。

### Windows

1. 前置条件：Windows 已安装、Tailscale 已连接、管理员 OpenSSH 可登录。
2. 通过 OpenSSH 下发固定 PowerShell bootstrap。
3. 创建自签名证书和 HTTPS PSRP listener，端口 `5986`，仅绑定当前 Tailscale IP。
4. 保留现有 Windows 防火墙全局状态；启用时增加 Tailscale scoped rule，关闭时验证 LAN/Wi-Fi 未监听 `5986`。
5. 验证 PSRP `win_ping` 后切换正式连接。
6. 管理员机器阶段安装 Git、PowerShell 7 和可选机器组件；不依赖 UAC 可见窗口。
7. 必要时使用 `win_reboot` 重启并等待 PSRP 恢复。
8. 普通用户阶段执行 Scoop、Profile、根 Stage 1 和 JSON 验证。

## 6. Secrets 集成

`powershellScripts-secrets` 是独立 Forgejo 用户私有仓库，不作为 submodule，避免在公开配置或 `.gitmodules` 中传播私有 URL。

建议结构：

```text
inventories/homelab/
├── group_vars/
│   └── windows.yml
└── host_vars/
    └── <host>.yml
```

允许按现有私有 Forgejo风险模型保存管理员密码和 Token；禁止保存 SSH 私钥。每个控制端独立生成 SSH 私钥，secrets 仓库只保存公钥/授权声明。

主仓库通过环境变量或忽略的本地配置解析 secrets checkout 位置，不提交绝对路径。加载前校验目录存在、Git remote 指向预期私有 Forgejo、工作树无意外未提交明文变更。

## 7. 安全与失败语义

- 默认 plan/check，不默认修改真实主机。
- 真实 apply 必须带单主机或小批量 `--limit`。
- 退出码 `1` 为失败，`2` 为参数错误，`10` 必须区分 RestartRequired 与外部 Blocked。
- Windows OpenSSH 到 PSRP 切换失败时保留原 SSH 通道，不删除或改写 SSH 端口。
- submodule 未初始化、dirty 或指针不在 GitHub 时，Ansible入口直接阻断。
- secrets 仓库误公开、Forgejo/控制端疑似入侵或旧机器退役时，轮换所有相关凭据。

## 8. Rollback

- Submodule：revert 父仓库 `.gitmodules`、gitlink、同步脚本和 QA 排除 commit；子仓库不受影响。
- Ansible：默认不 apply；已 apply 的 Windows PSRP bootstrap 可删除 Tailscale-IP listener、证书和对应防火墙规则，SSH 保持可用。
- Provisioning：平台安装脚本继续拥有自身备份与恢复合同；Ansible 不另写不可逆安装逻辑。
- Secrets：私有仓库只负责分发，不自动轮换；泄露时从被控系统重新签发凭据并提交替换值。

## 9. 未采用方案

- pyinfra：Windows 插件当前不适合生产级三平台管理。
- 在 `powershellScripts` 复制 Ansible control plane：会产生重复 inventory、连接配置和角色边界。
- Forgejo 作为 `powershellScripts` 主仓库并 push mirror GitHub：会引入 force mirror 语义并弱化 GitHub 公共协作边界。
- GitHub/Forgejo 双 push：不能解决父仓库同时读取两个代码库的需求，且存在部分成功状态。
- 使用 Forgejo mirror 作为 submodule URL：可能滞后，且把私人网络可达性带入公开依赖。
- 把 secrets 仓库做成 submodule：会暴露私有 URL并让普通初始化流程尝试拉取明文凭据仓库。
