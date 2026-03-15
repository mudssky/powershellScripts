- 每个代码改动任务完成时，执行根目录 `pnpm qa` 修复出现的问题；如果只修改了文案，不用执行 `qa`。
- 若改动涉及 pwsh 相关内容（如 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`、`PesterConfiguration.ps1`、`docker-compose.pester.yml`），提交代码前执行 `pnpm test:pwsh:all`。
- 如需显式验证 coverage 门槛或改动涉及 coverage 规范，额外执行 `pnpm test:pwsh:coverage`。
- 若本机 Docker 不可用，至少执行 `pnpm test:pwsh:full`（兼容保留，当前等价 `pnpm test:pwsh:coverage`），并在说明中明确 Linux 覆盖依赖 CI 或 WSL。
- 你必须为所有输出的代码补充清晰规范的注释。公共接口标注核心功能、入参、返回值，非直观逻辑补充设计意图，- 不重复代码本身的语义。
- 创建skill时使用中文，除了术语等

当创建或更新 `openspec/changes/**` 与 `openspec/specs/**` 下的 OpenSpec 工件（`proposal.md`、`design.md`、`tasks.md`、`specs/**/*.md`、`validation.md`）时：

1) OpenSpec 模板中的 Markdown 标题与小节名保持英文原文，不做翻译（如 `Why`、`What Changes`、`Context`、`Goals / Non-Goals`、`Decisions`、`Risks / Trade-offs`、`Migration Plan`、`Open Questions`、`Impact`、`Capabilities`、`New Capabilities`、`Modified Capabilities`）。
2) OpenSpec 结构关键词与固定术语保持原样（`ADDED Requirements`、`MODIFIED Requirements`、`REMOVED Requirements`、`RENAMED Requirements`、`Requirement`、`Scenario`、`WHEN`、`THEN`、`BREAKING`）。
3) 除上述标题、关键词与固定术语外，其余叙述必须使用简体中文。
4) 代码、命令、路径、参数名保持原样。
