# Design: docker-management Skill

> 关联 `prd.md`。本文件记录技术设计：目录契约、SKILL.md 路由机制、各 reference 内容契约、平台扩展机制、`linux/wsl2` 配置设计、交叉引用与回滚。

## 1. 架构与边界

两块交付物，单任务内完成：

1. **Skill 包**（`ai/skills/dev/docker-management/`）：自包含、可移植的 agent 操作知识库。纯 Markdown，无构建产物、无运行时依赖。
2. **`linux/wsl2` 配置刷新**：方案 C 在本仓库的「参考实现」，独立于 skill 存在（skill 自带配置示例，不引用仓库路径）。

边界：

- skill 不依赖仓库其它路径（可移植）。允许与 `docs/cheatsheet/` 内容交叉（受众不同，见 PRD「定位澄清」）。
- 不改 `shell/shared.d/proxy.sh`；不改 `docs/cheatsheet/`。
- 不写可执行 CLI；备份/迁移以命令片段 + 决策清单呈现。

## 2. SKILL.md 设计（路由契约）

### Frontmatter

```yaml
---
name: docker-management
description: 管理 Docker 运行方案的选型、配置、迁移与日常运维。Use when 用户要选择/对比 Docker 运行方案（Docker Desktop / Rancher Desktop / WSL2 纯 CLI）、配置 WSL2+Docker Engine+Portainer、从 Docker Desktop 迁移、决定是否备份镜像与数据卷、做容器日常运维（资源限制/日志/端口安全绑定/清理/代理）或排查 Docker 故障。
---
```

### 正文结构（精简，只做路由）

1. **使用时机**：一句话定位 + 不适用场景（不是 docker 入门教程）。
2. **第一步：确定平台**。路由表：

   | 平台 | 状态 | 入口 |
   |---|---|---|
   | Windows | ✅ 本期 | `references/platforms/windows.md` |
   | macOS | ⏳ 待补充 | `references/platforms/macos.md`（规划） |
   | Linux | ⏳ 待补充 | `references/platforms/linux.md`（规划） |

3. **第二步：按主题路由**（跨平台）：
   - 选型对比 → `references/runtime-options.md`
   - 迁移 / 要不要备份 → `references/migration-strategy.md`（+ 平台步骤回 `platforms/<os>.md`）
   - 日常运维 → `references/daily-ops.md`
   - 命令 / compose → `references/commands.md`
   - 故障排查 → `references/troubleshooting.md`
4. **安全护栏**：迁移/删除卷/卸载 Docker Desktop 等高风险操作，先确认备份再执行；命令默认非破坏，破坏性操作显式标注。

### 两级路由约定（扩展机制的核心）

- 平台相关深度内容只允许出现在 `platforms/<os>.md`。
- 跨平台主题文件用「平台差异注记」块（如 `> Windows: …` / `> macOS: …`）承载差异，不为某平台单独拆文件。
- 新增平台 = 新增 `platforms/<os>.md` + 在 SKILL.md 路由表与 `runtime-options.md` 矩阵补一列/一行。**不动**其它文件。

## 3. Reference 文件内容契约

### 3.1 `runtime-options.md`（跨平台选型）

- 决策矩阵：行=方案（Docker Desktop / Rancher Desktop / WSL2-CLI+Portainer / 各平台原生方案），列=平台（Windows ✅ / macOS ⏳ / Linux ⏳）+ 维度（License/商用授权、资源占用、GUI、k8s、容器引擎、网络模式、适用人群）。
- 「怎么选」决策树：是否需 GUI / 是否在意 Docker Desktop 商用授权 / 是否要极致轻量纯 CLI → 指向方案。
- 每方案一句话优劣 + 链到对应 `platforms/<os>.md` 的安装节。

### 3.2 `platforms/windows.md`（本期核心，最大文件）

分四节：

1. **三方案安装与取舍**：Docker Desktop（授权说明）、Rancher Desktop（dockerd/moby vs containerd 选择）、方案 C 总览。
2. **方案 C 完整配置最佳实践**（自包含配置示例）：
   - 启用 WSL2、安装发行版；`.wslconfig`（资源限制 + mirrored + autoMemoryReclaim/sparseVhd 等，附比例建议）。
   - `/etc/wsl.conf`：`[boot] systemd=true`、`[automount] options="metadata"`、可选 boot 启动 docker。
   - 在 WSL2 内安装 Docker Engine（官方源步骤，ctx7 核实）+ 用户加入 docker 组 + `systemctl enable --now docker`。
   - 部署 Portainer CE（compose / run 命令，数据卷持久化，端口安全绑定 `127.0.0.1`）。
   - 代理：指向 `shell/shared.d/proxy.sh` 的 `proxy on` / `proxy docker`（daemon 拉取代理）/ `proxy container`（容器运行代理）。
   - 端口 localhost 安全绑定（与 `docker-bind-localhost.md` 一致）。
   - 「本仓库参考实现」指针：`linux/wsl2/.wslconfig`、`linux/wsl2/wsl.conf`、`linux/wsl2/loadWslConfig.ps1`。
3. **迁移步骤（Windows）**：Docker Desktop → Rancher Desktop；Docker Desktop → 方案 C。每条含：停服 → （按 `migration-strategy.md` 决策）备份 → 切换运行时 → 校验 → 卸载 Docker Desktop（含 `wsl --unregister docker-desktop*` 注意点）。
4. 回链 `migration-strategy.md` 与 `daily-ops.md`。

### 3.3 `migration-strategy.md`（跨平台迁移与备份）

- **备份决策树**（与 PRD 表一致）：先列全部对象 → 默认是否备份 → 决策依据 → 「需要：进入备份流程 / 不需要：跳过」。
- **按对象的备份 + 恢复命令**（跨平台一致部分）：
  - 镜像：`docker save` / `docker load`（仅本地构建无 registry 的）；公共镜像→重拉。
  - 命名卷：`docker run --rm -v <vol>:/data -v $PWD:/backup alpine tar czf /backup/<vol>.tar.gz -C /data .` + 恢复逆操作。
  - bind mount：直接拷贝宿主目录。
  - compose + `.env`：版本管理则跳过，否则拷贝。
  - 整盘（Windows 专属）：`wsl --export docker-desktop-data`（标注为 Windows-only 差异块）。
- **通用迁移原则**：停写 → 备份校验（恢复演练）→ 切换 → 数据/服务校验 → 清理旧运行时。
- 平台特定步骤回链各 `platforms/<os>.md`。

### 3.4 `daily-ops.md`（跨平台运维）

- 资源限制（容器 `--memory`/`--cpus`；Desktop/WSL 层资源）。
- 日志轮转（daemon.json `log-driver`/`max-size`/`max-file`；compose `logging`）。
- 端口安全绑定 `127.0.0.1`（呼应 `docker-bind-localhost.md`）。
- 清理：`docker system prune` / `image prune` / `volume prune` 风险与用法（破坏性，显式标注）。
- 代理：指向 `shell/shared.d/proxy.sh`。

### 3.5 `commands.md`

- 常用命令速查（容器/镜像/卷/网络/日志/exec）。
- compose 工作流速查（up/down/logs/ps/profiles），呼应仓库 `start-container.ps1` + `config/dockerfiles/compose/` 实践（作为示例，不作依赖）。

### 3.6 `troubleshooting.md`

- 常见问题 playbook：daemon 起不来（WSL systemd 未开）、拉取超时（代理）、端口占用/无法访问、卷权限、磁盘膨胀（sparseVhd/prune）、mirrored 网络问题。
- 每条：症状 → 定位命令 → 处置；含平台差异注记。

## 4. `linux/wsl2` 配置设计

### 4.1 `.wslconfig`（刷新）

- 在现有 mirrored 基础上补回并注释：`swap`、`autoMemoryReclaim=gradual`、`sparseVhd=true`、`nestedVirtualization=true`、可选 `guiApplications`。
- 校正区块：当前 WSL 版本 `networkingMode`/`dnsTunneling`/`firewall`/`autoProxy` 应在 `[wsl2]` 顶层（非 `[experimental]`）——实现前 ctx7 核实当前键位归属。
- `memory`/`processors` 保留本机值但加比例注释（25%-50% 内存、50% 逻辑核）。
- 备份：修改前按 AGENTS.md，对本机面向配置先建带时间戳 `.bak`（`.wslconfig` 属本机配置）。

### 4.2 新增 `wsl.conf` 模板

- 路径：`linux/wsl2/wsl.conf`（仓库模板）；文件头注释说明部署到发行版内 `/etc/wsl.conf`。
- 内容：`[boot] systemd=true`；`[automount] options="metadata"`；可选 `[boot] command` / `[user] default`。
- 可选：补 `loadWslConfig.ps1` 的姊妹说明或不动（仅文档说明部署方式，避免越界改脚本）。

### 4.3 孤儿 `proxy.sh`

- `git mv linux/wsl2/proxy.sh linux/wsl2/deprecated/proxy.sh`。
- 在 `deprecated/proxy.sh` 顶部加注释：已退役，现役代理见 `shell/shared.d/proxy.sh`（`proxy on/off/docker/container`）。

## 5. 交叉引用方案

- skill **内部**用相对路径互链（可移植）：`platforms/windows.md` ↔ `migration-strategy.md` ↔ `daily-ops.md`。
- skill 指向**仓库资产**时，仅作为「本仓库参考实现」提示（`shell/shared.d/proxy.sh`、`linux/wsl2/*`），并说明「独立项目可忽略」，不形成硬依赖。

## 6. 关键权衡

- **自包含 vs DRY**：选自包含（用户决策）。skill 配置示例与 `linux/wsl2` 实际配置会重复；以「skill=权威可移植、wsl2=本机实现」分工，靠 PRD/design 记录保持一致，不做自动同步。
- **平台子目录 vs 平铺**：选 `platforms/` 子目录，避免主题×平台笛卡尔积文件爆炸。
- **完整范围 vs YAGNI**：用户要完整范围；靠渐进式披露（SKILL.md 瘦、references 厚）控制单文件复杂度，避免一个巨型文件。

## 7. 回滚考虑

- skill 为新增目录，回滚=删除 `ai/skills/dev/docker-management/`，无副作用。
- `linux/wsl2/.wslconfig` 改动有 `.bak` 备份，可还原。
- `proxy.sh` 用 `git mv`，回滚=移回原位。
- 全部为文档/配置，无代码逻辑、无测试回归风险。

## 8. 时效性核实清单（实现前 ctx7）

- WSL `.wslconfig` 当前键位归属（`[wsl2]` vs `[experimental]`）与 `autoMemoryReclaim`/`sparseVhd` 现状。
- WSL `wsl.conf` `systemd=true` 与在 WSL2 跑 Docker Engine 的当前推荐。
- Rancher Desktop 当前版本：容器引擎选择（moby/dockerd vs containerd）、Windows 安装方式。
- Docker Desktop 迁移/卸载在 Windows 的当前步骤、`docker-desktop` WSL 发行版名。
- Portainer CE 当前安装命令与镜像 tag。
