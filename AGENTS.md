- 每个代码改动任务完成时，执行根目录 `pnpm qa` 修复出现的问题；如果只修改了文案，不用执行 `qa`。
- 若改动涉及 pwsh 相关内容（如 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`、`PesterConfiguration.ps1`、`docker-compose.pester.yml`），提交代码前执行 `pnpm test:pwsh:all`。
- 如需显式验证 coverage 门槛或改动涉及 coverage 规范，额外执行 `pnpm test:pwsh:coverage`。
- 若本机 Docker 不可用，至少执行 `pnpm test:pwsh:full`（兼容保留，当前等价 `pnpm test:pwsh:coverage`），并在说明中明确 Linux 覆盖依赖 CI 或 WSL。
- 修改本地配置文件前，必须先在同目录创建带可读时间戳且以 `.bak` 结尾的备份文件，例如 `litellm.local.yaml.2026-05-29_09-58-00.bak`；适用范围包括 `*.local.*`、`.env.local`、`*.local.yaml`、`*.local.json`、`*.local.toml` 等只面向本机的配置文件。


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

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->
