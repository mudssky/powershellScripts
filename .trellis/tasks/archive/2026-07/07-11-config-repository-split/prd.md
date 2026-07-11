# 配置仓库拆分与按需分发设计

## Goal

基于当前仓库的真实体积、历史、装机依赖和平台目录现状，确定是否拆分新的个人配置仓库，并为首次装机下载、平台入口组织、Windows/WSL 边界和仓内归档给出可执行决策。

本任务只形成仓库边界决策，并把实施要求路由到现有平台流水线和归档子任务；不直接创建新仓库或搬迁代码。

## Background

- 当前仓库同时承载 PowerShell 模块、跨平台脚本、个人配置、安装自动化、独立工具、测试、文档和 Trellis 任务资料。
- 用户最初考虑拆出更纯粹的配置仓库，以减少首次装机时的无关内容和目录噪音。
- 讨论后确认：现有 Git 体积可以接受，完整历史和相关文档仍有价值；共享实现按领域分布也可以接受，只需保证平台专属入口集中。
- 已有 macOS、Linux/WSL、Windows、统一编排、网络源和冷归档子任务，可承接具体实施，不应在本任务建立第二套并行方案。

## Evidence

### 仓库体积

- 2026-07-11 本机工作目录约 `1.3 GB`，其中 `.git` 约 `28 MB`。
- Git 跟踪约 `2113` 个文件，当前跟踪内容合计约 `15 MB`；历史约 `1833` 次提交。
- 本机物理占用主要来自可重建或本机内容：`projects/` 约 `562 MB`、`node_modules/` 约 `442 MB`、`ai/` 约 `171 MB`。
- Git 历史中未发现主导体积的大型 blob；拆仓不能解决本机依赖和构建缓存占用。

### 装机依赖

- 装机入口和直接依赖横跨根 `install.ps1`、`Manage-BinScripts.ps1`、`macos/`、`linux/`、`profile/`、`shell/`、`config/`、`scripts/pwsh/`、`scripts/bash/`、`psutils/` 与少量 `projects/clis/` 工具。
- 按上述宽路径计算约 `2.98 MiB / 601` 个跟踪文件；体积不大，但物理搬移会改变相对路径、workspace、构建和 QA 合同。
- `psutils`、Profile、shell 配置与应用清单同时服务装机和日常运行，不应为了视觉集中复制或搬入单一装机目录。

### 平台边界

- `macos/` 已集中 macOS 编号安装入口、说明、Hammerspoon、登录项和 Quick Actions。
- `linux/` 已集中 Linux、Arch、Ubuntu 与 WSL 的现有入口和配置。
- 当前没有顶层 `windows/` 安装目录；Windows 装机职责分散在根安装器、Profile installer、AutoHotkey、winget Bootstrap 和共享脚本中。
- `linux/wsl2/loadWslConfig.ps1` 实际修改 Windows 用户目录并执行 `wsl --shutdown`，属于宿主职责；同目录的 `installPwsh.sh`、`wsl.conf` 与服务脚本属于 WSL 客体职责。

### Git 获取与历史

- sparse-checkout 只改变同一仓库的工作树可见范围，不会把目录变成独立仓库；partial clone 缺失的 blob 会在 checkout、merge、blame 等操作需要时继续下载。
- 当前装机依赖跨多个共享目录，维护 sparse path 清单会与流水线结构持续耦合，而受跟踪内容总量只有约 `15 MB`。
- shallow clone 可以独立减少首次装机的历史下载，不改变完整工作树或远端历史。
- 仓内归档使用 Git 跟踪的路径移动，内容和提交历史不会消失；单文件跨重命名历史可用 `git log --follow -- <path>` 查看。归档不会减少 clone 体积。

## Decision

### 保留单仓库

- 当前阶段不拆分新的配置仓库。
- 保留现有 monorepo、完整 Git 历史和仍有价值的相关文档。
- 只有未来出现独立发布周期、权限隔离、维护所有权或复用边界需求时，才重新评估拆仓。

### 保持领域共享与平台入口分层

- 不新增统一 `setup/` 门面，也不大规模物理聚合共享实现。
- `psutils/`、`profile/`、`shell/`、`config/` 和 `scripts/` 继续作为跨平台领域真源。
- `macos/`、`linux/` 与未来的 `windows/` 只拥有平台入口、平台特有配置、步骤说明和验证。

### 拆分 Windows 宿主与 WSL 客体职责

- Windows 宿主上的 WSL 安装、启用、发行版管理、`.wslconfig` 部署和 shutdown/restart 入口归 `windows/wsl/`。
- WSL 发行版内部的软件包、PowerShell、shell、服务与 `/etc/wsl.conf` 归 `linux/wsl/`。
- Windows 流水线完成宿主准备后，显式移交给 Linux/WSL 流水线。

### 首次装机使用浅克隆

- 远程 `00bootstrap` 默认使用 `git clone --depth=1`。
- 手工开发 clone 保持完整历史。
- 装机 checkout 需要旧历史时显式执行 `git fetch --unshallow`。
- 当前不启用 sparse-checkout 或 partial clone，不维护平台路径白名单。

### 按原计划执行仓内归档

- `07-10-repository-archive-batch` 继续按已批准清单执行，不因本任务暂停。
- 归档目标继续使用根级 `archive/<原始相对路径>`，并通过 `archive/README.md` 记录原路径、原因、替代入口和批准批次。
- 归档内容保留 Git 跟踪与可搜索性，但退出默认 workspace、构建、测试、格式化、lint 和发布流程。

## Requirements

- 平台入口使用统一编号语义，并由对应平台目录集中维护。
- 平台脚本只包装共享能力，不复制包清单、网络源、Profile、shell 或安装函数。
- Windows 流水线必须新增顶层 `windows/`，并落实 Windows/WSL 宿主与客体边界。
- macOS、Windows、Linux/WSL 的远程 Stage 0 Bootstrap 使用相同 shallow clone 语义，并允许覆盖 repo URL 与目标目录。
- shallow clone 失败时必须明确报错，不静默降级为下载来源不明的脚本快照。
- 归档移动优先保留可识别的 Git rename，更新仓内引用和归档索引；不得删除已批准归档内容的历史。
- 归档、平台目录整理和 clone 优化分别由现有子任务实施，本任务不重复创建实现清单。

## Downstream Routing

| 现有任务 | 新增或确认的实施要求 |
|---|---|
| `07-10-macos-install-pipeline` | 远程 `00bootstrap.zsh` 默认 `git clone --depth=1` |
| `07-10-windows-install-pipeline` | 新增顶层 `windows/` 编号入口；宿主 WSL 能力放入 `windows/wsl/`；远程 Bootstrap 默认 shallow clone |
| `07-10-linux-wsl-install-pipeline` | WSL 客体能力收敛到 `linux/wsl/`；接收 Windows 宿主流水线移交；远程 Bootstrap 默认 shallow clone |
| `07-10-unified-install-orchestrator` | 继续复用平台目录与共享领域真源，不新增 `setup/` 目录合同 |
| `07-10-repository-archive-batch` | 按原批准清单执行 `archive/` 迁移并让归档退出默认 QA |

## Execution Order

1. 完成共享前置合同；网络源任务已完成，统一编排器按依赖提供 Stage 1 接口。
2. 完成 `07-10-macos-install-pipeline`，形成首个平台参考实现。
3. 完成 `07-10-linux-wsl-install-pipeline`，落实 Linux 发行版与 WSL 客体边界。
4. 最后完成 `07-10-windows-install-pipeline`，同时落实顶层 `windows/`、WSL 宿主能力和 shallow clone。
5. `07-10-repository-archive-batch` 可独立执行，不阻塞平台顺序。

## Acceptance Criteria

- [x] 已区分工作目录、跟踪内容和 `.git` 历史体积，并识别主要本机占用来源。
- [x] 已比较保留单仓库、sparse/partial clone 与新建仓库的收益和代价。
- [x] 已明确当前阶段不拆仓，并保留完整历史和相关文档。
- [x] 已定义共享领域目录与平台入口目录的所有权边界。
- [x] 已定义 Windows 宿主与 WSL 客体的目录和流水线移交边界。
- [x] 已确定远程 Bootstrap 使用 shallow clone，开发 clone 使用完整历史。
- [x] 已确认仓内归档继续按原计划执行，且不会删除 Git 历史。
- [x] 已将实施要求路由到现有子任务，不在本任务重复实现。
- [x] 用户已审阅并确认最终规划结论与实施顺序。

## Out of Scope

- 创建或初始化新的远程仓库。
- 在本任务直接移动 Windows、WSL 或归档文件。
- 在本任务实现任何平台 Bootstrap 或统一安装器。
- 清理 `node_modules`、Rust target、测试报告等本机生成内容。
