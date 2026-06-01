# Implement: docker-management Skill

> 关联 `prd.md`、`design.md`。本文件是执行计划：有序清单、校验命令、风险点、回滚点。

## 前置：时效性核实（必须先做）

按全局规则用 `ctx7` 核实，结果记入对应 reference 草稿（避免凭 2026-01 旧记忆写错步骤）：

```bash
npx ctx7@latest library "WSL" "wslconfig wsl.conf systemd docker engine best practice"
npx ctx7@latest library "Rancher Desktop" "windows install container engine moby vs containerd"
npx ctx7@latest library "Docker Desktop" "windows uninstall migrate wsl distro"
npx ctx7@latest library "Portainer" "CE install docker run compose"
# 取最佳 ID 后 docs；每问 ≤3 命令
```

核实清单见 `design.md` 第 8 节。无法核实的点在文中标注「以官方文档为准」并给官方链接，不臆造。

## 实施顺序

### 阶段 A：骨架与 SKILL.md

- [ ] A1. 建目录：`ai/skills/dev/docker-management/references/platforms/`。
- [ ] A2. 写 `SKILL.md`：frontmatter（见 design §2）+ 使用时机 + 平台路由表（Windows ✅ / macOS ⏳ / Linux ⏳）+ 主题路由 + 安全护栏。保持精简。

### 阶段 B：跨平台主题文件（与平台无关，可先写）

- [ ] B1. `references/runtime-options.md`：三方案决策矩阵（含平台列，仅 Windows 行填实，macOS/Linux 留位）+「怎么选」决策树。
- [ ] B2. `references/migration-strategy.md`：备份决策树（对齐 PRD 表）+ 按对象备份/恢复命令 + 通用迁移原则 + 平台步骤回链。
- [ ] B3. `references/daily-ops.md`：资源限制/日志轮转/localhost 绑定/prune/代理（代理指向 `shell/shared.d/proxy.sh`）。
- [ ] B4. `references/commands.md`：命令速查 + compose 工作流。
- [ ] B5. `references/troubleshooting.md`：故障 playbook（含平台差异注记）。

### 阶段 C：Windows 平台文件（核心）

- [ ] C1. `references/platforms/windows.md`：四节（三方案取舍 / 方案 C 完整配置 / 迁移步骤 / 回链）。配置示例自包含，与 `linux/wsl2` 改动保持一致。

### 阶段 D：linux/wsl2 配置刷新

- [ ] D1. 备份：`cp linux/wsl2/.wslconfig "linux/wsl2/.wslconfig.$(date +%Y-%m-%d_%H-%M-%S).bak"`（本机面向配置，AGENTS.md 要求）。
- [ ] D2. 刷新 `linux/wsl2/.wslconfig`：补 `swap`/`autoMemoryReclaim=gradual`/`sparseVhd=true`/`nestedVirtualization`，校正区块键位（按 ctx7），加比例注释。
- [ ] D3. 新增 `linux/wsl2/wsl.conf`：`[boot] systemd=true` + `[automount] options="metadata"`，文件头注明部署到 `/etc/wsl.conf`。
- [ ] D4. `git mv linux/wsl2/proxy.sh linux/wsl2/deprecated/proxy.sh`，在退役文件顶部加注释指向 `shell/shared.d/proxy.sh`。

### 阶段 E：一致性自检

- [ ] E1. 校验 `platforms/windows.md` 的配置示例与 `linux/wsl2/.wslconfig` + `wsl.conf` 内容一致。
- [ ] E2. 校验 skill 内部相对链接、回链可达；SKILL.md 路由表与实际文件吻合。
- [ ] E3. 校验 `daily-ops.md` localhost 绑定结论与 `docs/cheatsheet/linux/docker/docker-bind-localhost.md` 不冲突。
- [ ] E4. 确认 `shell/shared.d/proxy.sh` 未被改动（`git status`）。

## 校验命令

```bash
# Markdown 格式（必须）
pnpm format:md

# 改动集中在 ai/skills/** 文档 + linux/wsl2 配置（非 pwsh 测试目标）。
# 主体为文档/配置，按 AGENTS.md「仅改文案可免 qa」；但本任务含 .wslconfig/wsl.conf 配置文件，
# 稳妥起见跑一次 qa（仅 lint/format，不应触发 pwsh 测试）：
pnpm qa            # 若 qa 判定无受影响包则快速通过

# 仅当改动意外落入 pwsh 范围（scripts/pwsh|profile|psutils|tests/*.ps1）才需：
# pnpm test:pwsh:all
```

判断：本任务不改 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`，预期**无需** `pnpm test:pwsh:all`。`linux/wsl2/*.sh` 的移动不改 `shell/shared.d`，不影响 shell 部署测试。

## 风险点与回滚

| 风险点 | 说明 | 回滚 |
|---|---|---|
| `.wslconfig` 改坏导致 WSL 起不来 | 区块/键位写错 | 还原 `.bak`，`wsl --shutdown` |
| 误改 `shell/shared.d/proxy.sh` | 影响原生 Linux 代理 | 不应触碰；E4 自检 + `git checkout` |
| 时效信息过时 | Rancher/Portainer/Docker 步骤变化 | ctx7 核实；不确定处标官方链接 |
| 自包含配置与 wsl2 实现漂移 | 两处重复不一致 | E1 自检对齐 |
| skill 内容范围蔓延 | 完整范围易写成巨型文件 | 渐进式披露，SKILL.md 瘦身，单文件聚焦 |

## 完成定义（对齐 PRD 验收标准）

- 1 个 `SKILL.md` + 6 个 reference 文件按骨架生成且内容中文。
- `linux/wsl2`：`.wslconfig` 刷新 + 新增 `wsl.conf` + `proxy.sh` 移入 `deprecated/`。
- `shell/shared.d/proxy.sh` 与 `docs/cheatsheet/` 未改。
- `pnpm format:md` 通过。
- PRD 验收清单逐条勾选。
