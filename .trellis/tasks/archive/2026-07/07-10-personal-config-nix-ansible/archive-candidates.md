# 归档候选清单

> 状态：第一批结构性冷归档已获用户批准，尚未执行任何文件移动。

## 判定规则

- `待确认归档`：已有替代入口或明确失效，且未发现活动引用。
- `待确认迁往知识库`：内容以通用知识、速查或学习资料为主，不是项目运行或维护契约。
- `暂缓`：存在活动引用、配置真源不清晰，或需要先完成替代方案。
- `保留`：满足个人工作流、配置真源、CLI/脚本准入或仓库工具入口要求。

任何归档、迁出或删除动作都必须在用户确认对应批次后执行。

## 第一批：结构性冷归档候选

| 对象 | 建议归属 | 理由 | 风险 | 验证方式 | 状态 |
|---|---|---|---|---|---|
| `deprecated/**` | `archive/deprecated/**` | 已有新版脚本入口，目录自 2025 年后无功能变更；文件名搜索只命中新版 `scripts/pwsh/media/concatflv.ps1` 与其文档 | 低：需要确认没有个人外部快捷方式直接指向旧路径 | 搜索旧文件名；运行 `Manage-BinScripts.ps1` dry-run 或同步检查 | 已批准归档，批次 1 |
| `profile/deprecated/**` | `archive/profile/deprecated/**` | 仅含旧 Linux Profile，现有 Profile 已模块化，未发现路径或文件名引用 | 低 | 搜索 `linuxprofile.ps1`；运行 Profile 相关测试 | 已批准归档，批次 1 |
| `macos/archive/**` | `archive/macos/archive/**` | 内容本身已标记归档，且合盖守卫有明确失败原因和 Hammerspoon 替代入口 | 低：需同步历史任务中的说明链接时才改引用 | 搜索 `macos/archive` 与具体文件名；运行 macOS 安装验证的 repo 阶段 | 已批准归档，批次 1 |
| `config/frontend/deprecated/**` | `archive/config/frontend/deprecated/**` | 仅保存旧 Biome v1/Prettier 配置，当前根配置使用 Biome 2，未发现引用 | 低 | 搜索 `biomev1.prettier.json`；运行当前 Biome 检查 | 已批准归档，批次 1 |
| `config/vscode/back/**` | `archive/config/vscode/back/**` | 单个历史 VS Code Vim 配置备份，未发现引用 | 低 | 搜索 `vim-back.jsonc`；确认当前 VS Code 配置入口 | 已批准归档，批次 1 |
| `linux/wsl2/deprecated/**` | `archive/linux/wsl2/deprecated/**` | 旧代理脚本已由 `shell/shared.d/proxy.sh` 替代；旧 `.wslconfig` 不应继续作为当前模板 | 中：`linux/wsl2/loadWslConfig.ps1` 当前仍引用同目录 `.wslconfig`，需要先确认其目标应改为新的 Docker 管理 skill 模板还是保留兼容文件 | 搜索 `.wslconfig`、`proxy.sh`；验证 WSL 配置部署入口 | 待确认归档，需先修入口 |
| `config/software/pixpin/deprecated/**` | `archive/config/software/pixpin/deprecated/**` | 日期化旧配置快照，未发现活动引用 | 低：可能仍承担人工回退用途 | 搜索快照文件名；确认当前 PixPin 配置源 | 已批准归档，批次 1 |

## 第二批：知识库迁移候选

| 对象 | 建议归属 | 理由 | 风险 | 验证方式 | 状态 |
|---|---|---|---|---|---|
| `docs/cheatsheet/**` | 外部知识库；`archive/README.md` 只保留映射 | 大部分是 Git、语言、框架、数据库、终端等通用速查，不属于项目运行契约 | 中：部分文档含本仓库特定说明或被其他文档引用，需要逐文件拆分 | 生成文件级迁移表；搜索相对链接；知识库落地后抽查链接 | 已记录，当前暂缓迁移 |
| `ai/docs/**` | 外部知识库；`archive/README.md` 只保留映射 | 主要是 AI 架构、RAG、评测、Prompt 方法与 Ollama 通用资料 | 低至中：需确认是否有 skill 直接引用 | 搜索 `ai/docs/` 引用；知识库落地后核对索引 | 已记录，当前暂缓迁移 |

### 迁移前必须留在项目侧的契约

以下文件不能直接随整个 cheatsheet 目录迁走，应先把项目专用内容迁到对应配置、脚本或 `.trellis/spec/`：

- `docs/cheatsheet/network/tailscale/index.md`：当前被 `tests/TailscaleDerpComposeTemplate.Tests.ps1` 直接读取，并记录 Tailscale/DERP 脚本入口。
- `docs/cheatsheet/vscode/remote/setup-ssh.md`：当前被 `Enable-WindowsOpenSsh.ps1` 的用户提示引用，并包含本仓 OpenSSH 脚本用法。
- `docs/cheatsheet/linux/docker/docker-bind-localhost.md`：包含本仓 `start-container.ps1` 的行为示例。
- `docs/cheatsheet/github/dependabot.md`：包含本仓实际 Dependabot 与 workspace 策略，通用模板与项目契约需要拆分。
- `docs/cheatsheet/vscode/remote/devcontainers.md`：直接指向 `config/vscode/devcontainers/` 模板。
- `docs/cheatsheet/security/betterleaks-guide.md`：说明根级 `.betterleaksignore` 的使用方式。
- `docs/cheatsheet/pwsh/script-template.ps1`：是项目脚本模板入口，宜迁到 `templates/` 而不是知识库。
- `docs/跨平台单文件脚本最佳实践.md` 及其链接页面：通用正文可迁往知识库，项目必须遵守的脚本约束应沉淀到 `.trellis/spec/`。

## 第三批：需要单独确认用途

| 对象 | 当前判断 | 原因 | 状态 |
|---|---|---|---|
| `.vercel/project.json` | 归档到 `archive/.vercel/project.json` | 仅含旧 Vercel 项目标识，2026 年无变更且未发现仓库引用；用户确认本仓已不再使用 Vercel 部署 | 已批准归档，批次 2 |
| `ipynb/renameLegal.ipynb` | 归档到 `archive/ipynb/renameLegal.ipynb` | 已有 `scripts/pwsh/filesystem/renameLegal.ps1` 作为受文档支持的直接替代入口，notebook 无活动引用 | 已批准归档，批次 2 |
| `docs/brainstorms/**`、`docs/ideation/**`、`docs/plans/**`、`docs/superpowers/**` | 可能冷归档 | 多数是旧规划过程，Trellis 已成为当前任务系统；但部分文档仍被现行设计或回滚说明引用 | 待逐目录做引用图 |
| `docs/todos/**` | 迁入 Trellis 或归档 | 待办不应与 Trellis 活动任务形成两套真源 | 待确认待办是否仍有效 |
| `openspec/**` | 暂缓 | 当前 PowerShell 测试、覆盖率和 shell 结构仍引用其正式规范；应先迁移有效契约到 `.trellis/spec/` 再讨论 | 暂缓 |
| `config/vscode/neovim/dreprecated/**` | 暂缓 | 目录名表示弃用，但当前 README 仍把其中脚本和 Lua 文件当作安装入口 | 暂缓，先修正文档与当前入口 |
| `ai/self-hosted/lobehub/deprecated/**` | 保留原位 | `start.sh`、`start.ps1` 和 README 仍把这些文件作为 internal 回滚模式，当前属于活动兼容路径 | 保留 |
| `ai/prompts/assistant/emotion/deprecated/**` | 保留原位 | 当前 changelog 直接链接这些历史版本，属于领域内版本沿革 | 保留 |
| `ai/skills/dev/powershellscripts-ops/references/deprecated/**` | 保留原位 | 活动 skill 明确路由到这些排障参考，移动会破坏 skill 自包含边界 | 保留 |

## 当前明确不按语言归档

- `projects/clis/**`：CLI 属于允许保留的个人工具资产，后续只按真实用途确认，不因 Rust/TypeScript 归档。
- `scripts/ahk/**`、`scripts/bash/**`、`scripts/node/**`、`scripts/python/**`：后续按工具逐项确认，不因非 PowerShell 归档。
- `linux/fnos/fnos-mount-manager/**`：有完整入口、测试和近期维护，当前保留。
- `ai/coding/**`、`ai/gateway/**`、`ai/skills/**`：当前存在活跃配置或工具链，不能整体归档。
- `config/**`、`profile/**`、`psutils/**`、`scripts/pwsh/**`、`shell/**`、`linux/**`、`macos/**`：属于仓库核心领域，只有内部明确失效单元进入候选表。
