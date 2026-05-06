- 每个代码改动任务完成时，执行根目录 `pnpm qa` 修复出现的问题；如果只修改了文案，不用执行 `qa`。
- 若改动涉及 pwsh 相关内容（如 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`、`PesterConfiguration.ps1`、`docker-compose.pester.yml`），提交代码前执行 `pnpm test:pwsh:all`。
- 如需显式验证 coverage 门槛或改动涉及 coverage 规范，额外执行 `pnpm test:pwsh:coverage`。
- 若本机 Docker 不可用，至少执行 `pnpm test:pwsh:full`（兼容保留，当前等价 `pnpm test:pwsh:coverage`），并在说明中明确 Linux 覆盖依赖 CI 或 WSL。
- 你必须为所有输出的代码补充清晰规范的注释。公共接口标注核心功能、入参、返回值，非直观逻辑补充设计意图，- 不重复代码本身的语义。

<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:

- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

## Subagents

- ALWAYS wait for every spawned subagent to reach a terminal status before yielding, acting on partial results, or spawning followups.
  - On Codex, this means calling the `wait` tool with the subagent's thread id (requires `multi_agent_v2`). Do NOT infer completion from elapsed time.
  - On Claude Code / OpenCode, this means awaiting the Task/agent tool result before continuing.
- NEVER cancel or re-spawn a subagent that hasn't finished. If a subagent appears stuck, raise the wait timeout (Codex default 30s, max 1h) before judging it broken.
- Spawn subagents automatically when:
  - Parallelizable work (e.g., install + verify, npm test + typecheck, multiple tasks from plan)
  - Long-running or blocking tasks where a worker can run independently
  - Isolation for risky changes or checks

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->
