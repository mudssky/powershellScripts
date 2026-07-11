# 个人配置仓库边界与 Nix Ansible 方案

## Goal

将本仓库收敛为“以个人配置与 PowerShell 脚本为核心，并承载精选 CLI 与跨平台自动化工具的个人环境仓库”，建立可持续的内容准入、冷归档、文档分类和跨平台装机边界，并明确 Ansible 与 Nix 是否值得引入以及各自职责。

## Background

- 用户计划长期在本仓维护个人配置、PowerShell 脚本、跨平台安装入口和仍有实际用途的 CLI/自动化工具。
- 冷内容需要继续保留在 Git 可见的 `archive/`，不能只依赖提交历史；通用知识文档未来迁往外部知识库，项目契约继续留在仓库。
- 仓库同时服务原生 Windows、macOS 与 WSL/Linux，不能按语言、平台或目录体积简单拆分。
- 方案应复用现有代码与安装入口，避免因引入 Ansible、Nix 或新仓库而形成第二套配置真源。

## Confirmed Facts

- 本仓是 pnpm workspace/Turborepo 管理的多语言 monorepo；`projects/**`、`scripts/node`、`scripts/bash`、`scripts/pwsh`、`psutils` 等参与统一构建或 QA。
- PowerShell 核心资产集中在根安装入口、`scripts/pwsh/`、`profile/`、`psutils/` 与 `tests/`，并直接依赖 `projects/clis/pwshfmt-rs` 等非 PowerShell 工具。
- Git 跟踪内容和历史体积可接受；主要本机占用来自 `node_modules`、Rust `target` 等可重建内容，拆仓不能解决这些占用。
- 当前阶段已决策保留单仓库、完整历史和领域共享目录；平台专属入口集中到 `macos/`、`linux/` 与 `windows/`。
- macOS、Linux/WSL、Windows 安装流水线、统一 Stage 1 编排器和 package source transaction 已完成并归档；Core/Full、步骤状态、失败重跑与验证入口已落地。
- 根级冷归档结构、QA 排除合同和两批已批准迁移已完成；实际结果记录在 [`archive/README.md`](../../../archive/README.md)，候选与暂缓项记录在 [`archive-candidates.md`](./archive-candidates.md)。
- 通用 `docs/cheatsheet/**` 与 `ai/docs/**` 的知识库迁移边界已记录，但用户决定暂缓实际迁移；其中的项目专用契约必须先迁回脚本、配置或 `.trellis/spec/`。
- Ansible 当前没有 playbook 或 inventory；其价值主要出现在服务器、NAS、多 WSL/Linux 实例等多主机编排场景，而不是单台个人设备本地初始化。
- Nix devshell 已完成 PRD、设计、实施计划、国内缓存调研和采用价值说明；用户决定暂缓实施。Nix 不作为现有安装链和父任务收敛的阻塞条件。

## Requirements

### 仓库准入边界

- 仓库以个人配置与 PowerShell 脚本为核心，同时允许保留满足真实用途的 CLI、跨平台脚本及其安装、测试、构建、规范和维护资产。
- CLI 与脚本满足以下任一条件时默认保留：被安装、Profile、QA 或配置链调用；具有仍在使用的命令入口；服务当前支持平台；或由维护清单明确标记为 active。
- 准入规则是唯一真源，不维护覆盖所有文件的静态白名单。只有用途不明确、未发现活动入口，或同时符合保留与归档条件的对象进入例外审查清单。
- 已被替代、无有效入口、无维护意愿或纯实验性的内容才可列为冷归档候选；实际移动前必须列明路径、目标、理由、风险和验证方式并获得用户批准。
- 生成物、缓存、本机运行数据和测试报告不进入源码归档，通过 ignore、重建或清理策略管理。
- 仍在维护但职责独立的项目必须与真正停止维护的历史内容分开；只有出现独立发布周期、权限、维护所有权或复用边界时才重新评估拆仓。

### 冷归档与文档

- 冷归档统一使用根级 `archive/<原始相对路径>`，内容继续由 Git 跟踪和搜索，但默认退出 workspace、构建、测试、格式化、lint 和发布流程。
- `archive/README.md` 固定记录批次、原路径、归档路径、原因、替代入口或恢复说明；不得从归档路径建立新运行入口。
- 项目运行、配置、维护和设计契约留在仓库；通用知识、速查和学习资料迁往知识库。
- 知识库迁移前必须拆出项目专用内容并修复引用；迁移后的正文不在 `archive/` 重复保留，只在索引中记录去向。
- `docs/cheatsheet/**`、`ai/docs/**`、旧计划、todos 和 OpenSpec 的后续迁移继续按例外清单逐批处理，本父任务不执行未批准批次。

### 平台与安装流程

- 原生 Windows、macOS 与 WSL/Linux 均是一等支持平台；Linux 同时覆盖开发环境与服务器自动化场景。
- 设备初始化采用两阶段模型：Stage 0 获得 Git、平台包管理器、PowerShell 与仓库；Stage 1 由根 PowerShell 编排器执行共享步骤和平台叶子。
- 平台入口使用统一编号、Core/Full 预设、可重复执行、状态汇总和失败重跑；Full 必须显式选择。
- 平台脚本复用包清单、source engine、Profile、shell 与安装函数，不复制业务逻辑。
- 网络良好时保持官方源；需要国内镜像时通过统一 source transaction 预览、应用、追踪和恢复，不在叶子脚本散落镜像 URL。
- 每台个人设备继续以本地 clone 并执行仓库入口为默认方式；远程装机可使用 shallow clone，开发 clone 保持完整历史。

### Ansible 边界

- Ansible 作为服务器、NAS、多 WSL/Linux 实例或其他多主机场景的可选编排层，不作为单台个人设备的默认入口。
- 若未来引入 Ansible，首期只调用现有 PowerShell/shell 叶子和统一编排器，不重写安装逻辑或包清单。
- Windows 默认继续本机执行；只有明确需要远程管理时才引入 SSH、WinRM 或 PSRP、inventory 和凭据生命周期。
- 当前不创建 Ansible playbook、inventory 或控制机配置。

### Nix 边界

- Nix 只保留为显式、可撤销的仓库开发环境试点，不接管用户主目录、Profile、shell rc、GUI、字体、系统设置或现有应用清单。
- 若恢复试点，只覆盖 Apple Silicon macOS 与 Ubuntu 24.04 WSL2 x86_64，通过 `nix develop` 提供 Node、pnpm、PowerShell/Pester、Rust/Cargo 和 Git 工具链。
- 原生 Windows 继续使用 PowerShell 和现有包管理器；Nix 不作为 `install.ps1`、Core/Full 或平台编号脚本的隐藏后端。
- Nix 必须与 Scoop、Winget、Chocolatey、Homebrew、Cargo 和现有安装链并存且可完整移除。
- 当前暂缓 Nix 实施；恢复条件、资源上限、source 回退与采用判定以 `07-10-nix-devshell-pilot` 任务为准。

## Task Map

| 子任务 | 交付物 | 状态 |
|---|---|---|
| `07-10-macos-install-pipeline` | macOS 编号安装、验证和共享步骤参考 | 已完成并归档 |
| `07-10-network-source-bootstrap` | source catalog、transaction、adapter、Stage 0 与恢复合同 | 已完成并归档 |
| `07-10-unified-install-orchestrator` | 根 Stage 1、Core/Full、步骤状态和重跑 | 已完成并归档 |
| `07-10-linux-wsl-install-pipeline` | Linux/WSL 编号步骤、宿主/客体边界和验证 | 已完成并归档 |
| `07-10-windows-install-pipeline` | Windows 编号步骤、PowerShell/CLI/字体/Profile/WSL 宿主 | 已完成并归档 |
| `07-10-repository-archive-batch` | 根 `archive/`、索引、批准迁移和 QA 排除 | 已完成并归档 |
| `07-11-config-repository-split` | 不拆仓、平台目录所有权和 shallow clone 决策 | 已完成并归档 |
| `07-10-nix-devshell-pilot` | 可复现 devshell、资源和回退试点 | 规划完成，实施暂缓 |

父任务只维护源需求、跨子任务决策和最终集成结论，不承担直接代码实现。

## Acceptance Criteria

- [x] 仓库内容边界和 CLI/脚本准入规则可判断新文件应保留、迁移还是放入其他项目，且无需维护全量静态白名单。
- [x] 已明确当前阶段保留单仓库、完整历史、领域共享目录和平台入口分层。
- [x] 归档方案包含目标位置、命名、索引、迁移审批和恢复规则，两批已批准迁移已落地。
- [x] 文档分类规则与候选表可区分项目文档、知识库候选和仓内冷归档；未批准迁移保持原位。
- [x] macOS、Linux/WSL、Windows、统一编排与网络源合同均已落地并完成子任务验收。
- [x] Ansible 与 Nix 的职责边界、重叠区域、不适用场景和渐进式采用条件均已明确。
- [x] Nix 采用建议与目标平台、资源容忍度和维护偏好匹配；低风险试点规划完成但按用户决定暂缓。
- [x] 父任务没有未解决的产品或范围问题；Nix 暂缓不影响现有仓库与安装流程继续使用。

## Out Of Scope

- 当前创建独立配置仓库、拆分 Git 历史或启用 sparse/partial clone。
- 当前实现 Ansible playbook、inventory 或远程凭据管理。
- 当前实施 Nix、Home Manager、nix-darwin 或 NixOS 配置。
- 未经新批次批准迁移 `docs/cheatsheet/**`、`ai/docs/**`、旧计划、todos 或 OpenSpec。
- 维护覆盖所有现有文件的静态白名单。
