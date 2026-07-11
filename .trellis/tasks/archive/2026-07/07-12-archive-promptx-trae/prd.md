# 归档 PromptX 与 Trae 项目配置

## Goal

将已退出活动维护的根 `.promptx`、`.trae` 与 `openspec` 迁入冷归档，维护 `archive/index.json`，并修复仍把这些路径当作当前项目入口的活动引用。确认空 `.vercel` 无需重复归档。

## Background

- `.promptx` 包含 27 个已跟踪文件，约 160 KiB；根目录未发现活动运行入口。
- `.trae` 包含 111 个已跟踪文件，约 672 KiB，混合历史文档、规则和 Trellis 生成的平台文件。
- `openspec` 包含 140 个已跟踪文件，约 660 KiB；OpenSpec 命令和 Claude skills 已在前序配置清理中移除。
- `.vercel/project.json` 已在批次 2 归档到 `archive/.vercel/project.json`，当前根 `.vercel` 为空目录。
- `project-archive plan` 已验证三个候选均可镜像迁移到 `archive/.promptx`、`archive/.trae` 与 `archive/openspec`。
- Trellis、Claude/Codex hooks 和 rule-loader 对 Trae 的通用支持仍有价值，不等于本仓库继续维护根 `.trae` 配置。

## Requirements

### R1. 归档根 PromptX 配置

- 使用 `project-archive archive .promptx --execute` 执行 `git mv` 并更新 JSON 索引。
- 批次为 3，原因记录为“根 PromptX 项目角色与资源已退出活动维护”。
- 恢复说明指向活动 PromptX MCP 配置位于 `ai/mcp`，同时说明归档内容仅供历史参考。
- 不修改 `scripts/ahk/.promptx` 独立子项目及其内部引用。

### R2. 归档根 Trae 配置

- 使用 `project-archive archive .trae --execute` 执行 `git mv` 并更新 JSON 索引。
- 批次为 3，原因记录为“本仓库已退出 Trae 项目配置维护”。
- 替代入口指向 `.agents/skills`，说明继续使用共享 agent skills 与现有 Claude/Codex 配置。
- 不删除 Trellis、Claude/Codex hooks、agent meta 文档或 rule-loader 中对 Trae 平台格式的通用支持。

### R3. 归档 OpenSpec

- 使用 `project-archive archive openspec --execute` 执行 `git mv` 并更新 JSON 索引。
- 批次为 3，原因记录为“OpenSpec 工作流已退出本仓库活动维护”。
- 替代入口指向 `.trellis`，说明使用 Trellis 任务、规范与工作流。
- 从 `turbo.json` 删除 3 条已无必要的 `!openspec/**` 专用排除。
- 从 `profile/installer/apps-config.json` 删除 npm 与 bun 两个 OpenSpec CLI 安装项。
- 将 `docs/plans/**` 中明确指向 `openspec/specs/**` 的路径迁移为 `archive/openspec/specs/**`，保留历史说明语义。
- 保留 `ai/coding/claude/docs/插件指南.md` 中对外部 OpenSpec 项目的通用介绍。

### R4. 活动引用迁移

- 从根 README 目录树移除 `.trae/` 当前配置入口。
- 将 `.betterleaksignore` 中 3 条 `.trae/documents/...` 路径改为 `archive/.trae/documents/...`，保持 secret 扫描例外精确匹配。
- 将 `docs/plans/2026-04-05-001-refactor-fnos-mount-manager-plan.md` 中当前可点击或事实性引用迁移到 `archive/.trae/documents/...`。
- 不改写 `.trellis/tasks/archive/**` 和 `scripts/node/.claude/archived_plans/**` 历史记录。
- 不修改 `.trellis/.template-hashes.json`；它是 Trellis 运行态保护清单，不属于本批次真源。

### R5. Vercel 状态

- 不新增 `.vercel` 索引项，不移动空目录，不创建占位文件。
- 验证现有 `batch-2-vercel-project` 索引和归档目标仍通过 `check`。

### R6. 验证

- `project-archive check` 必须通过，索引总数从 8 增至 11。
- 源目录 `.promptx`、`.trae`、`openspec` 消失，镜像目标存在且由 Git 跟踪。
- `.vercel` 不包含跟踪文件，现有 Vercel 归档记录不变。
- 运行 `pnpm qa`；本任务不修改 PowerShell 代码，不要求 `pnpm test:pwsh:all`。
- 抽查 `git diff --summary` 和 `git log --follow`，确认迁移保持 rename 可追溯性。

## Acceptance Criteria

- [x] `.promptx` 完整迁移到 `archive/.promptx` 并登记为批次 3。
- [x] `.trae` 完整迁移到 `archive/.trae` 并登记为批次 3。
- [x] `openspec` 完整迁移到 `archive/openspec` 并登记为批次 3。
- [x] `archive/index.json` 包含 11 条唯一、有效的归档记录。
- [x] README、betterleaks 和当前计划文档不再把根 `.trae` 当作活动路径。
- [x] Turbo 与应用安装清单不再保留 OpenSpec 活动入口，历史 spec 链接指向归档镜像。
- [x] Trae 通用平台支持与 `scripts/ahk/.promptx` 保持不变。
- [x] 空 `.vercel` 未产生重复索引或占位文件。
- [x] `project-archive check`、`pnpm qa` 和 Git 历史抽查通过。

## Out Of Scope

- 不移除 Trae 平台适配代码、测试或通用文档。
- 不归档 `scripts/ahk/.promptx`。
- 不删除外部 OpenSpec 项目的通用介绍或历史讨论文字。
- 不修改或清理其他 agent 平台目录。
