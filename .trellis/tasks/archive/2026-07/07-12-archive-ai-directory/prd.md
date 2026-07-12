# 审计并归档 AI 目录

## Goal

让整个 `ai/` 功能域退出本仓库的活动维护。将其全部 Git 跟踪内容迁移到根目录镜像归档路径 `archive/ai/`，并清理本仓库中的 workspace、脚本、测试和文档活动入口；相关能力后续在其他仓库维护。

## Background

- `ai/` 当前约 171 MB，包含 agents、coding、docs、gateway、mcp、prompts、self-hosted、skills 以及模型下载脚本等多个相互独立的功能域。
- `pnpm-workspace.yaml` 当前包含 `ai/skills/dev/*`。
- `Manage-BinScripts.ps1` 当前扫描 `ai/**/*.ps1` 及 `ai/coding/claude/*.ps1`。
- `tests/Sync-ClaudeConfig.Tests.ps1`、`tests/SkillsInstaller.Tests.ps1`、`tests/LiteLLMStart.Tests.ps1` 分别直接依赖 `ai/coding`、`ai/skills`、`ai/gateway` 下的活动入口。
- `README.md` 和 `CLAUDE.md` 将 `ai/` 描述为当前 AI 工具目录。
- 归档索引 `archive/index.json` 当前通过归档工具校验，共有 82 条有效记录。
- 用户已确认整个 `ai/` 应退出本仓库，而不是仅归档其中失效的子路径；原有活动引用需要同步退役。
- 用户已确认不记录具体替代仓库，仅说明相关能力已迁往其他仓库。
- `ai/` 当前有 315 个 Git 跟踪文件。
- `ai/` 下存在未跟踪或忽略的本机配置、secret、虚拟环境和依赖目录，包括 `.env.local`、LobeHub `.env`、本地 LiteLLM YAML、`.venv` 和 `node_modules`。

## Requirements

- 使用项目归档工具对候选路径先执行只读 `plan`，确认目标镜像路径、Git 跟踪状态和活动引用。
- 归档 `ai/` 下的全部 Git 跟踪内容，不再保留本仓库内的活动 AI 工具入口。
- 删除 `pnpm-workspace.yaml`、`Manage-BinScripts.ps1`、`powershellScripts.code-workspace`、根 README/CLAUDE 文档和 lockfile 中对 `ai/` 的活动引用。
- 删除仅验证已归档 AI 工具的专属测试；不得把测试改为引用 `archive/ai/`，以免归档路径重新成为运行入口。
- 将仅适用于已归档 AI 工具的活动 Trellis 规范作为独立归档对象迁出 `.trellis/spec/infra/`，并从规范索引移除。
- 归档目标必须保持源路径镜像结构，即 `ai/<path>` 迁移到 `archive/ai/<path>`。
- `archive/index.json` 必须记录整个 `ai/` 功能域退出本仓库维护，替代说明为“相关能力已迁往其他仓库”，不添加具体链接。
- 不归档缓存、secret、本机运行数据、生成物或依赖目录。
- 将归档移动与活动引用清理拆为独立提交，避免在移动提交中改写归档文件正文。
- 保留当前工作区中与本任务无关的未跟踪目录和用户改动。

## Acceptance Criteria

- [ ] `ai/` 下全部 315 个 Git 跟踪文件均迁移到 `archive/ai/` 镜像路径，原 `ai/` 不再包含 Git 跟踪内容。
- [ ] `pnpm-workspace.yaml`、lockfile、脚本默认扫描范围、工作区配置、专属测试及仓库文档不再将 `ai/` 作为活动入口。
- [ ] 仓库活动路径不存在对 `ai/` 的有效引用；历史文本或第三方示例中的同名字符串不计入。
- [ ] Hermes、LiteLLM、coding window warmer 和 agent skill 开发规范不再作为活动 infra 规范出现，并各自拥有独立归档索引条目。
- [ ] `archive/index.json` 包含整个 `ai/` 归档对象的结构化条目，并通过归档工具 `check`。
- [ ] Git 能正确识别迁移，归档提交不混入正文重写或无关文件。
- [ ] 本机 `.env*`、本地 YAML、`.venv`、`node_modules` 等忽略内容未进入 Git 归档；任务报告明确它们仍留在原路径或已由用户另行处理。
- [ ] 完成 `pnpm qa` 和 `pnpm test:pwsh:all`。
- [ ] 最终报告列出归档内容、移除的入口、未纳入归档的本机内容及恢复方式。

## Out Of Scope

- 不把缓存、依赖、secret 或本机运行状态纳入 Git 归档。
- 不在本仓库为 AI 工具建立新的替代实现。
- 不以文件类型重新分类归档内容。
- 不猜测或创建其他仓库的链接、submodule 或同步机制。
