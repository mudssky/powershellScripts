# PRD: WSL Docker PowerShell Bridge

## 目标与用户价值

补齐 `docker-management` skill 中漏掉的 Windows 兼容性问题：从 Docker Desktop 迁移到「WSL2 内 Docker Engine」之后，Windows PowerShell 里的既有项目脚本仍应尽量能直接调用 Docker，至少要有清晰、可诊断的降级路径。

用户价值是避免迁移后所有 Windows 工作区都被迫搬到 WSL 内开发，尤其是本仓库和其他 Windows 项目里的 `pnpm` / `.ps1` 脚本仍大量直接执行 `docker`、`docker compose`。

## 确认事实

### 官方能力边界（ctx7 / Docker CLI 文档）

- Docker CLI 支持用 `-H/--host` 或 `DOCKER_HOST` 指向不同 daemon。
- Docker CLI host 协议支持 `unix://`、`tcp://`、`ssh://`，Windows 默认是 `npipe:////./pipe/docker_engine`。
- `docker context create` 可创建 `tcp://...` 或 `ssh://...` 的 Docker 上下文，并用 `docker context use` 或 `docker --context ...` 切换。
- `docker compose` 支持 `--project-directory`，默认相对路径以第一个 compose 文件所在路径为基准。

### 仓库现有 Docker 调用

- `package.json` 的 `test:pwsh:linux:*` 直接执行 `docker compose -f docker-compose.pester.yml ...`。
- `docker-compose.pester.yml` 会把当前仓库目录挂载到 Linux 容器：`.:/workspace`。
- `scripts/pwsh/devops/start-container.ps1` 会检测 `docker` / `docker compose`，并通过 `& docker ...` 执行 compose、inspect、port、ps 等命令。
- `config/dockerfiles/compose/docker-compose.yml` 大量使用 `${DATA_PATH}` bind mount，例如 `${DATA_PATH}/postgresql:/var/lib/postgresql`。
- 多个网关和自托管脚本（如 `ai/gateway/*/start.ps1`、`ai/self-hosted/lobehub/start.ps1`）也从 Windows PowerShell 直接调用 `docker compose`。

## 核心问题

WSL2 内 Docker Engine 可以作为 daemon 被 Windows 侧 Docker CLI 连接，但这不自动等价于“Windows 项目脚本全部兼容”。

风险点：

- Docker Desktop 卸载后，Windows 侧可能没有 `docker.exe` / compose 插件，`Get-Command docker` 会失败。
- 即使安装了 Windows Docker CLI，默认 `npipe` daemon 不存在，必须配置 context、`DOCKER_HOST` 或 wrapper。
- 如果 Windows CLI 连接的是 WSL 内 daemon，bind mount 源路径必须能被 WSL/Linux daemon 理解；`C:\...`、相对路径 `.`、`${DATA_PATH}` 的语义可能和 Docker Desktop 不同。
- 直接暴露 `tcp://127.0.0.1:2375` 方便但有安全边界，不能默认暴露到局域网。
- `wsl.exe -d <distro> docker ...` wrapper 能复用 WSL 内 CLI，但仍要处理 Windows 当前目录到 `/mnt/c/...` 的路径转换，以及环境变量路径转换。

## 需求

1. `docker-management` skill 必须明确回答：Docker Desktop 迁到 WSL2-only 后，Windows PowerShell 能否继续直接调用 Docker。
2. 文档必须重点记录两类调用模式：
   - 方案 C：Windows Docker CLI 连接 WSL daemon：`docker context` / `DOCKER_HOST`，适合无复杂 bind mount 或路径已转换的场景，但 TCP / SSH 连接配置较麻烦。
   - 方案 D：PowerShell wrapper 转发到 WSL 内 `docker`：适合保留 Windows 命令入口，但需要路径转换策略。
3. 文档必须给出推荐默认：迁移到 WSL2-only 但仍要从 PowerShell 启动 Windows 项目时，预计优先走方案 D；方案 C 保留为备选。
4. 对本仓库要单独列出兼容性检查清单：
   - `docker version`
   - `docker compose version`
   - `docker compose -f docker-compose.pester.yml config`
   - `docker compose -f docker-compose.pester.yml run --rm pester-fast`
   - `scripts/pwsh/devops/start-container.ps1` 的 dry-run 或最小 profile 启动
   - `${DATA_PATH}` 指向 Windows 路径、WSL 路径时的差异
5. 如果最终实现 wrapper 或诊断脚本，公共函数必须遵守本仓库规范，标注核心功能、入参、返回值，复杂逻辑用中文注释说明设计意图。

## 已决策

- 默认路线：**优先让 Docker 相关项目脚本在 WSL 内直接运行**。这是 WSL2-only Docker Engine 最直接、路径语义最稳定的使用方式。
- 可选路线：当项目必须继续从 Windows PowerShell 启动时，再选择 Windows Docker CLI + context/`DOCKER_HOST`，或 PowerShell wrapper 转发到 WSL 内 `docker`，让现有 Windows 项目脚本尽量继续可用。
- 例外路线：当项目存在大量 bind mount、复杂构建上下文、相对路径或 Linux 测试容器，且路径转换成本高于收益时，应明确建议该项目转到 WSL 内运行脚本，而不是强行启用 wrapper。
- 迁移说明不能只写“能连 daemon”，必须把路径兼容性验证列入验收，避免 `docker ps` 成功但 `docker compose up` 或测试容器挂载失败。
- Rancher Desktop 不纳入方案 C / D。它是 Docker Desktop 的替代桌面运行时，不是把 Windows PowerShell 桥接到用户自有 WSL 发行版内 dockerd 的工具。

## 验收标准

- [ ] `ai/skills/dev/docker-management` 增加 Windows PowerShell 调用 WSL Docker Engine 的专题说明。
- [ ] 专题说明包含方案 C：`docker context` / `DOCKER_HOST`，以及方案 D：`wsl.exe` wrapper 的取舍。
- [ ] 专题说明明确 Rancher Desktop 在纯 WSL dockerd 路线中不是核心组件。
- [ ] 专题说明明确 bind mount 路径风险，并给出 Windows 路径与 WSL 路径兼容性检查方法。
- [ ] `references/platforms/windows.md` 在 Docker Desktop → WSL2-CLI 迁移步骤中加入“PowerShell 入口兼容性验证”。
- [ ] `references/commands.md` 或新增专题文件提供最小验证命令，能判断 Windows PowerShell 中的 `docker compose` 是否真的可用。
- [ ] 若新增或修改 `scripts/**/*.ps1`，执行 `pnpm test:pwsh:all`；若只改文档，按仓库规则可免 `qa`。

## 不在范围内

- 本轮不直接迁移所有 Windows 项目的 compose 文件。
- 本轮不强制把所有开发迁到 WSL 内。
- 本轮不默认开放 Docker daemon 到 `0.0.0.0:2375`。
- 本轮不自动卸载 Docker Desktop 或注销 `docker-desktop*` WSL 发行版。

## 待决策问题

- 已选择方案 D wrapper：skill 内提供 `Invoke-WslDocker.ps1` 与 `docker.ps1` shim；profile 暂不自动注册 `docker` wrapper，避免隐式改变每个 Windows PowerShell 会话的 Docker 语义。
