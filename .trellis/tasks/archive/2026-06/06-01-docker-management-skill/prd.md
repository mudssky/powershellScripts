# PRD: Docker 管理 Skill 封装

## 目标与用户价值

封装一个**面向 agent 的、自包含、可移植**的 Docker 管理 Skill（`ai/skills/dev/docker-management`），帮助用户与 AI agent 完成 Docker 运行方案的**选型、配置、迁移与日常运维**。本期实现 **Windows 平台**（Docker Desktop / Rancher Desktop / WSL2-CLI+Portainer 三方案），并按「平台可扩展」设计骨架，便于后续加入 macOS / Linux。同时全面刷新 `linux/wsl2` 目录下的最佳实践配置，作为方案 C 在本仓库的参考实现。

## 确认事实（来自代码库调研）

### Skill 现有规范（`ai/skills/dev/`）

- Skill 目录结构：`SKILL.md`（frontmatter + 主流程/路由）+ `references/*.md`（详细文档）+ 可选 `scripts/`、`src/`、`examples/`。
- `SKILL.md` frontmatter 格式：`name`、`description`（含「Use when ...」触发描述，中文）。
- 两种典型形态：
  - **知识/方法论型**（如 `organize-classify`）：SKILL.md 写工作流程 + 方法路由，`references/` 存分主题详细文档，无可执行脚本。
  - **工具型**（如 `database-query`）：SKILL.md 写 CLI 用法，含 `scripts/`、`src/`、`references/`，有可执行命令。
- 正文中文，注释中文。

### 现有 WSL2 / Docker 资产

- `linux/wsl2/.wslconfig`：当前配置 `networkingMode=mirrored`、`dnsTunneling=true`、`firewall=true`、`autoProxy=true`、`memory=16GB`、`processors=4`。
- `linux/wsl2/loadWslConfig.ps1`：复制 `.wslconfig` 到 `%USERPROFILE%` 并 `wsl --shutdown`。
- `linux/wsl2/proxy.sh`：从 `/etc/resolv.conf` 取主机 IP 设置 http(s)_proxy（7890 端口）。
- `linux/wsl2/installer/installPwsh.sh`、`linux/wsl2/deprecated/.wslconfig`。
- `docs/cheatsheet/win/wsl.md`：已有 133 行 WSL2 配置速查表（`.wslconfig` vs `wsl.conf` 对比、常用配置）。
- `docs/cheatsheet/linux/docker/docker-bind-localhost.md`：已有 473 行 Docker 端口 localhost 绑定文档。

### 现有 Docker 工作流（决定迁移章节的备份对象）

- `scripts/pwsh/devops/start-container.ps1` + `config/dockerfiles/compose/`：用 docker compose（profiles + `.env`）启动开发容器。
- 当前环境：**Windows 11 + Docker Desktop**。
- 实际运行服务：redis / postgres / mongo / minio 等开发数据库；数据卷挂在 `DATA_PATH` 下（如 `${DATA_PATH}/postgresql/data`）。
- 推论：迁移真正要保护的是这些**开发库的数据卷与 compose 配置**，镜像多为公共镜像（可重新 pull）。

## 需求来源（用户初步描述）

1. Windows 下三种 Docker 方案对比：方案 A Docker Desktop / 方案 B Rancher Desktop / 方案 C WSL2 + Docker(CLI) + WebUI（纯 CLI）。
2. 方案 C（WSL2 纯 CLI）的详细配置与最佳实践，衔接现有 WSL2 配置。
3. Docker Desktop 迁移流程：先决策「是否备份镜像和数据卷」→ 需要则走备份流程、否则跳过；目标为方案 B 或 C。
4. 更新 `linux/wsl2` 目录下的最佳实践配置文件。
5.（追加）后续需扩展 macOS / Linux 平台，结构需预留。

## 已决策

- **Skill 形态：知识/方法论型**（如 `organize-classify`）。仅含 `SKILL.md` + `references/*.md`，无需构建的 CLI 工具。备份/迁移以「可复制命令片段 + 决策清单」形式写进 references，保留人工决策点，不做全自动黑盒脚本。零构建依赖、易维护，符合 KISS。
- **方案 C 的 WebUI：Portainer CE**（能管镜像/容器/数据卷/网络，迁移备份章节查数据卷直接可用）。
- **内容架构：skill 完全自包含**。skill 的 `references/` 持有权威内容（含配置示例），可独立安装携带。`linux/wsl2` 配置文件作为「本机实际配置」单独更新，与 skill 推荐保持一致；`docs/cheatsheet` 维持现状。接受 skill 与仓库间的少量有意重复。
- **迁移路径：仅从 Docker Desktop 出发** → 两条目标路径（→ Rancher Desktop、→ WSL2-CLI）。不覆盖 Rancher ↔ WSL2-CLI 互转。
- **备份决策树（先全列出，再按默认值/依据决定走不走备份流程）**：

  | 对象 | 默认是否备份 | 决策依据 |
  |---|---|---|
  | 数据卷（named volume / bind mount 数据） | 要 | 有不可再生数据（DB 数据等）→ 必备份 |
  | compose 配置 + `.env` | 要（多数已在仓库） | 已版本管理则跳过 |
  | 自建/本地构建镜像 | 视情况 | 仅本地构建且无 Dockerfile/registry → 要；公共镜像 → 跳过（重拉） |
  | 容器本身 | 否 | 由 compose/镜像重建，不备份 |
  | Docker Desktop 的 WSL 发行版整体 | 可选 | 想整盘搬迁可 `wsl --export docker-desktop-data` |

- **`linux/wsl2` 改动：全面刷新**。① `.wslconfig` 补回 `autoMemoryReclaim=gradual`/`sparseVhd`/`swap`/`nestedVirtualization` 并加比例注释、修正 `[experimental]` 区块为当前语法；② 新增 `wsl.conf` 模板（`systemd=true`、`automount metadata`、boot 启动 docker）；③ 孤儿 `proxy.sh` 移入 `deprecated/`。

## 关键技术差距（调研结论，将写入内容）

- 方案 C 在 WSL2 内直接跑 Docker Engine，几乎必须在 `/etc/wsl.conf` 开 `systemd=true`；当前 `linux/wsl2` 无 `wsl.conf` 模板。
- `deprecated/.wslconfig` 含当前版本未保留的好选项：`autoMemoryReclaim=gradual`、`sparseVhd=true`、`nestedVirtualization`、`swap`、`guiApplications`。

## ⚠️ proxy.sh 重要发现（影响 wsl2 改动方案）

- 仓库存在两个 `proxy.sh`，地位不同：
  - **`shell/shared.d/proxy.sh`（生效版）**：`shell/deploy.sh` 部署、WSL2 与原生 Linux 共用。已默认 `127.0.0.1:7890`、跨平台、mode 无关，支持 `PROXY_DEFAULT_HOST/PORT`、自动探测、`proxy docker` / `proxy container` 子命令。**不应改动**——这保证原生 Linux 不受影响。
  - **`linux/wsl2/proxy.sh`（孤儿）**：11 行，硬编码解析 `/etc/resolv.conf` 主机 IP（WSL2 NAT 时代做法）。grep 确认无任何 `source` 引用，不在 deploy/加载链路里，仅 WSL2 目录内自带。
- 结论：原「修 proxy.sh 适配 mirrored」改为「**孤儿文件移入 `linux/wsl2/deprecated/`**」（与旧 `.wslconfig` 并列，保留历史），并在 wsl2 说明/skill 里指向 `shell/shared.d/proxy.sh` 为现役代理管理器。`shell/shared.d/proxy.sh` 不改动。

## Skill 范围（已决策：完整范围 C）

- **定位澄清**：skill ≠ cheatsheet。cheatsheet（`docs/cheatsheet/`）面向人速查；skill 面向 agent，是自包含、可移植的操作知识库。两者内容交叉属正常，不视为重复。
- **完整范围**，至少覆盖：
  1. 三方案选型对比（Docker Desktop / Rancher Desktop / WSL2-CLI+Portainer）。
  2. 方案 C 配置最佳实践（WSL2 + Docker Engine + systemd + Portainer）。
  3. Docker Desktop 迁移流程 + 备份决策树（→ Rancher / → WSL2-CLI）。
  4. 日常运维最佳实践（资源限制、日志轮转、localhost 端口安全绑定、`prune` 清理、代理）。
  5. 命令速查 / compose 工作流。
  6. 故障排查 playbook。
- 用渐进式披露组织：`SKILL.md` 精简（使用时机 + 路由），深度内容拆到 `references/*.md`。

## 平台扩展性（重要结构约束）

- **本期实现 Windows**（三方案），但 **macOS / Linux 平台后续要加入**。
- skill 目录结构必须从一开始就按「平台可扩展」设计：加 macOS / Linux 时只需新增平台文件，不动跨平台主题文件与 `SKILL.md` 主干。
- 平台差异分布：
  - 强平台相关：**选型方案集合**（各 OS 可选 runtime 不同）、**安装配置最佳实践**、**迁移的具体步骤**（Docker Desktop 在各 OS 卸载/迁移方式不同）。
  - 基本跨平台：**备份/恢复决策树**、**日常运维原则**、**命令/compose 速查**、**故障排查通用项**（含平台差异注记）。

## 命名与任务结构（已决策）

- **Skill 名**：`docker-management`（kebab-case，与现有 skill 命名一致）。
- **目录骨架（平台可扩展）**：

  ```
  ai/skills/dev/docker-management/
  ├── SKILL.md                   # 使用时机 + 两级路由（先平台，再主题）
  └── references/
      ├── runtime-options.md     # 跨平台选型总览：决策矩阵（行=方案 列=平台）
      ├── platforms/
      │   └── windows.md         # 本期：三方案细节 + 方案C 配置 + DockerDesktop 迁移步骤
      ├── migration-strategy.md  # 跨平台：备份决策树 + 通用迁移原则 + 恢复命令
      ├── daily-ops.md           # 跨平台运维：资源限制/日志轮转/localhost绑定/prune/代理
      ├── commands.md            # 命令速查 + compose 工作流
      └── troubleshooting.md     # 故障排查 playbook
  ```

  - macOS / Linux **本期不建空壳**；仅在 `SKILL.md` 路由表标「待补充」，扩展时新增 `platforms/macos.md`、`platforms/linux.md`。
- **任务结构**：单任务交付「skill」+「`linux/wsl2` 配置刷新」两块（wsl2 改动小且与方案 C 强耦合，不拆 parent/child）。
- **时效性**：实现前用 `ctx7` 核实 Rancher Desktop / WSL systemd / Docker Desktop 迁移卸载 / Portainer 安装的当前用法（知识截止 2026-01，今 2026-06）。

## 验收标准

- [ ] `ai/skills/dev/docker-management/SKILL.md` 存在，frontmatter 含 `name: docker-management` 与中文 `description`（含「Use when …」触发语），正文为「使用时机 + 两级路由」，保持精简。
- [ ] `references/` 按骨架生成 6 个文件（`runtime-options.md`、`platforms/windows.md`、`migration-strategy.md`、`daily-ops.md`、`commands.md`、`troubleshooting.md`），内容中文。
- [ ] `runtime-options.md` 含三方案决策矩阵（含平台列，Windows 行已填、macOS/Linux 列留可扩展位）。
- [ ] `platforms/windows.md` 覆盖：三方案安装/取舍；方案 C 完整配置（`.wslconfig`、`/etc/wsl.conf` 的 `systemd=true`、Docker Engine 安装、Portainer CE 部署、localhost 安全绑定）；Docker Desktop → Rancher / → WSL2-CLI 的迁移步骤，并回链 `migration-strategy.md`。
- [ ] `migration-strategy.md` 含「要不要备份」决策树（与 PRD 备份表一致）、按对象的备份/恢复命令（镜像 `docker save/load`、数据卷 tar、compose/.env），明确「需要→流程 / 不需要→跳过」分支。
- [ ] `daily-ops.md` 的 localhost 端口安全绑定与现有 `docs/cheatsheet/linux/docker/docker-bind-localhost.md` 结论一致；代理一节指向 `shell/shared.d/proxy.sh`（`proxy on/off/docker`）。
- [ ] `linux/wsl2/.wslconfig` 已刷新（补回 `autoMemoryReclaim`/`sparseVhd`/`swap`/`nestedVirtualization`，区块语法为当前 WSL 版本，含比例注释）。
- [ ] 新增 `linux/wsl2/wsl.conf`（或带说明的模板），含 `[boot] systemd=true`、`[automount] options="metadata"`，并说明部署到 `/etc/wsl.conf`。
- [ ] `linux/wsl2/proxy.sh` 已移入 `linux/wsl2/deprecated/`，原位置不再保留；wsl2 说明指向 `shell/shared.d/proxy.sh`。
- [ ] `shell/shared.d/proxy.sh` 未被改动（原生 Linux 行为不变）。
- [ ] 所有 Markdown 通过 `pnpm format:md`（rumdl）。
- [ ] 改动涉及 `linux/**` 的 shell/配置，但不触碰 pwsh 测试目标；若改动落入 pwsh 范围则按 AGENTS.md 跑 `pnpm test:pwsh:all`。文案/文档类改动按规则可免 `qa`。

## 不在范围内

- macOS / Linux 平台的实际内容（仅预留结构，后续任务补）。
- Rancher Desktop ↔ WSL2-CLI 互转迁移（仅覆盖从 Docker Desktop 出发）。
- 可执行的备份/迁移自动化 CLI 工具（采用命令片段 + 决策清单，保留人工决策）。
- 改写 `shell/shared.d/proxy.sh` 或新增第二套代理逻辑。
- 修改 `docs/cheatsheet/` 现有文档。
- 完整的 docker/compose 入门教程（skill 面向已会基本概念的 agent/用户）。

## 待澄清的阻塞性问题

- 无（核心决策已全部确认）。规划进入 `design.md` / `implement.md`。

## 决策记录（已确认）

1. Skill 形态 → 知识/方法论型（无构建 CLI）。
2. 方案 C WebUI → Portainer CE。
3. 内容架构 → skill 完全自包含（skill ≠ cheatsheet）。
4. 迁移路径 → 仅 Docker Desktop → {Rancher, WSL2-CLI}；备份采用决策树表。
5. `linux/wsl2` → 全面刷新；孤儿 `proxy.sh` 移入 `deprecated/`；`shell/shared.d/proxy.sh` 不动。
6. Skill 范围 → 完整范围（含运维/命令/故障排查）。
7. 结构 → 平台可扩展（`platforms/` 子目录 + 跨平台主题文件）；本期仅 Windows。
8. 命名 `docker-management`；单任务交付。
