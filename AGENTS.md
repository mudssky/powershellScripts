每个任务完成时，执行根目录pnpm qa修复出现的问题

当创建或更新 `openspec/changes/**` 与 `openspec/specs/**` 下的 OpenSpec 工件（`proposal.md`、`design.md`、`tasks.md`、`specs/**/*.md`、`validation.md`）时：

1) OpenSpec 模板中的 Markdown 标题与小节名保持英文原文，不做翻译（如 `Why`、`What Changes`、`Context`、`Goals / Non-Goals`、`Decisions`、`Risks / Trade-offs`、`Migration Plan`、`Open Questions`、`Impact`、`Capabilities`、`New Capabilities`、`Modified Capabilities`）。
2) OpenSpec 结构关键词与固定术语保持原样（`ADDED Requirements`、`MODIFIED Requirements`、`REMOVED Requirements`、`RENAMED Requirements`、`Requirement`、`Scenario`、`WHEN`、`THEN`、`BREAKING`）。
3) 除上述标题、关键词与固定术语外，其余叙述必须使用简体中文。
4) 代码、命令、路径、参数名保持原样。
