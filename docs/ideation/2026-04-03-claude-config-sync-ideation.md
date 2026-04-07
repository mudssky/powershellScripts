---
date: 2026-04-03
topic: claude-config-sync
focus: Claude Code 配置同步、settings.json 拆分、敏感信息隔离
---

# Ideation: Claude 配置同步安全化

## Codebase Context

- 当前同步入口是 `ai/coding/claude/Sync-ClaudeConfig.ps1`，它会把 `ai/coding/claude/.claude` 整体链接到 `~/.claude`。
- 当前已跟踪的 `ai/coding/claude/.claude/settings.json` 包含 `env.ANTHROPIC_API_KEY` 与 `env.ANTHROPIC_BASE_URL`，说明敏感配置与共享配置仍混在同一文件内。
- `ai/coding/claude/.claude` 目录除了共享资产，还承载了 backup、history、debug、sessions、transcripts 等运行态数据；虽然 `ai/coding/claude/.gitignore` 已对部分目录做黑名单排除，但边界仍然脆弱。
- 仓库已经存在更安全的配置分层先例：`ai/coding/claude/config/user.settings.json` 可作为可提交模板；根 `.gitignore` 也已接受 `*.local.json`、`.env.local`、`env.ps1` 等本机覆盖约定。

## Ranked Ideas

### 1. 将 `settings.json` 改为“模板 + 本机覆盖 + 生成产物”
**Description:** 仓库只保留可提交的基础配置模板，本机额外维护不入库的覆盖文件，最终由脚本生成真实 `~/.claude/settings.json`。
**Rationale:** 这是最直接解决 secrets 泄漏风险的办法，同时保留当前 router / 直连两种使用模式。
**Downsides:** 需要新增合并规则、文件命名约定与迁移脚本。
**Confidence:** 95%
**Complexity:** Medium
**Status:** Explored

### 2. 把整目录软链接改成白名单同步
**Description:** 不再把整个 `.claude` 目录映射到用户目录，只同步 `CLAUDE.md`、`commands/`、`skills/`、`output-styles/` 等共享资产。
**Rationale:** 可以从同步机制上阻断运行态数据和敏感文件被仓库“顺带管理”的问题。
**Downsides:** 需要维护白名单，脚本复杂度略高于整目录软链。
**Confidence:** 92%
**Complexity:** Medium
**Status:** Unexplored

### 3. 引入 provider profile 切换层
**Description:** 为 `router`、`direct-anthropic` 等场景定义 profile，主配置不再直接手改敏感 env。
**Rationale:** 很契合“有时走 router，有时需要在 env 里直接加密钥”的现状。
**Downsides:** 会引入一层新的概念，初期理解成本略高。
**Confidence:** 88%
**Complexity:** Medium
**Status:** Unexplored

### 4. 为同步脚本增加 secret guardrail
**Description:** 在同步前扫描 `settings.json`、`.claude/**` 中的 key/token/header 等高风险字段，命中后阻止同步或要求迁移到本地覆盖文件。
**Rationale:** 即使做完分层，也需要兜底防止误提交与误同步。
**Downsides:** 需要权衡误报与漏报，规则要持续维护。
**Confidence:** 90%
**Complexity:** Low
**Status:** Unexplored

### 5. 将运行态数据彻底移出仓库托管边界
**Description:** 仓库内只保留共享配置资产，真实 `~/.claude` 下的 history / debug / sessions / transcripts 永远不参与同步。
**Rationale:** 可以从根源上明确“哪些是配置、哪些是状态”。
**Downsides:** 需要一次性清理和迁移已有目录。
**Confidence:** 94%
**Complexity:** Medium
**Status:** Unexplored

### 6. 保留黑名单目录，但继续扩充 `.gitignore`
**Description:** 维持当前整目录思路，只在 `.gitignore` 中补更多敏感路径和缓存目录。
**Rationale:** 改动最小，短期能减少一部分误提交。
**Downsides:** 仍然依赖人为维护黑名单，无法解决已跟踪文件与目录职责混杂的问题。
**Confidence:** 72%
**Complexity:** Low
**Status:** Unexplored

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | 继续扩充 `.gitignore` 黑名单 | 只能持续补洞，无法解决 `settings.json` 已跟踪且可含密钥的根因问题 |
| 2 | 把完整 `.claude` 放到单独私有仓库 | 会把共享配置与项目上下文拆散，降低可发现性与维护一致性 |
| 3 | 依赖加密文件提交密钥 | 安全性更强，但对当前仓库是过度设计，协作与脚本复杂度偏高 |
| 4 | 完全改为系统凭据管理器 | 跨平台一致性较差，不适合作为当前脚本仓库的默认入口 |
| 5 | 继续保留整目录同步，只增加人工审查 | 仍然容易因误操作把新敏感字段带入仓库 |

## Session Log

- 2026-04-03: Initial ideation - 11 个候选方向进入筛选，最终保留 6 个候选方案。
- 2026-04-03: 用户选择“拆分 `settings.json`”作为下一步，进入 brainstorm，方案 1 标记为 Explored。
