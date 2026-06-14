# 迁移仓库运维 skill 到 dev 并支持全局定位

## Goal

将现有 `.agents/skills/repo-ops` 迁移到 `ai/skills/dev/powershellscripts-ops`，纳入本仓库通用 skill 安装体系，让它通过现有安装器安装到用户级 global scope。全局安装后的 `powershellscripts-ops` 仍必须能定位回本仓库根目录 `/Users/mudssky/projects/env/powershellScripts`，以便执行 LiteLLM、LobeHub、Forgejo、n8n、项目依赖安装等仓库管理任务。

核心用户价值：

- 新 Agent 会话不在本仓库目录时，也能发现并触发 `powershellscripts-ops`。
- 仓库运维 skill 不再只作为 `.agents/skills/` 下的项目级能力存在，而是进入 `ai/skills/dev/` 的统一开发和安装流。
- 用户可以安装到全局，不需要手动复制 skill 目录。
- 全局触发时，Agent 能知道应回到哪个仓库目录执行命令。

## Confirmed Facts

- 仓库已有通用 skill 安装器：`ai/skills/Install-Skills.ps1`，默认读取 `ai/skills/skills.config.json`。
- `ai/skills/skills.config.json` 默认 `scope` 是 `global`，默认 agent 是 `claude` 与 `codex`。
- 安装器会将友好名 `claude` 映射为 `claude-code`，`codex` 保持为 `codex`，并生成 `npx --yes skills add <source> --global --agent ... --yes`。
- 安装器支持本地 skill 来源、`-IncludeDevAll` 自动发现 `ai/skills/dev/*/SKILL.md`、`-DryRun` 预览、`-Yes` 跳过确认、`-Force` 强制执行、`-Name` 过滤单项。
- `skills` CLI 文档确认 `add` 支持 `--global` 用户级安装、`--agent` 选择目标 agent、`--skill` 选择 skill、`--copy` 复制而不是软链接；本仓库安装器已封装这些参数。
- 仓库已有项目管理类 skill：`.agents/skills/repo-ops`，用于 LiteLLM、LobeHub、Forgejo、n8n、自托管运维、项目依赖安装和维护本地 `repo-ops` skill。
- 仓库已有 Trellis 管理类 skill：`.agents/skills/trellis-*`，但它们目前不在 `ai/skills/skills.config.json` 中。
- 当前用户级 Codex skill 目录 `~/.codex/skills` 没有安装本仓库 `.agents/skills/repo-ops` 或 Trellis skill。
- `ai/skills/dev/` 已经是可跨 agent 复用的个人 skill 开发目录，且被 `pnpm-workspace.yaml` 纳入 workspace。
- `.trellis/spec/infra/agent-skill-dev.md` 要求新脚本型 skill 的安装态入口必须可直接运行，不依赖未构建源码或隐式依赖；纯文档 skill 可以只有 `SKILL.md`、`references/`、`examples/`。
- 本机已安装的 `~/.codex/skills/database-query` 是复制目录，不是指向 `ai/skills/dev/database-query` 的软链接；因此全局安装后的 `powershellscripts-ops` 不能默认依赖目录链接反查仓库位置。
- 用户已明确首批范围只包含 `repo-ops`，不包含 Trellis skill，也不是新增单独的安装器 skill。
- 用户重新判断后确认：该 skill 的主要价值是全局可用；不推荐同时安装到 project scope，避免重复入口。
- 全局名称 `repo-ops` 过泛，最终命名改为 `powershellscripts-ops`。

## Requirements

- 将 `.agents/skills/repo-ops` 的完整内容移动到 `ai/skills/dev/powershellscripts-ops`，并将 frontmatter `name` 改为 `powershellscripts-ops`。
- 更新 skill 说明，把维护来源调整为 `ai/skills/dev/powershellscripts-ops`。
- 在 `powershellscripts-ops` 中加入全局安装态的仓库定位规则，至少覆盖当前仓库根目录 `/Users/mudssky/projects/env/powershellScripts`。
- 将 `powershellscripts-ops` 加入 `ai/skills/skills.config.json`，默认通过现有安装器安装到 global。
- 保留或更新 `agents/openai.yaml`，确保 UI 元数据仍匹配迁移后的 skill。
- 更新仓库内引用 `.agents/skills/repo-ops` 的文档、任务说明或维护说明，避免后续 Agent 继续修改旧路径。
- 文档中明确不推荐 project scope 重复安装。
- 不新增 Trellis skill 的全局安装配置。
- 不新增单独的 `repo-skill-installer` skill。

## Acceptance Criteria

- [ ] `prd.md` 记录目标、已确认事实、需求、验收标准、范围外事项和开放问题。
- [ ] 若范围被判定为复杂任务，补充 `design.md` 与 `implement.md` 后再开始实现。
- [ ] `ai/skills/dev/powershellscripts-ops/SKILL.md` 和所有 reference 文件存在，旧 `.agents/skills/repo-ops` 不再作为真实维护来源。
- [ ] `ai/skills/skills.config.json` 显式包含 `powershellscripts-ops` 本地 skill，来源指向 `./dev/powershellscripts-ops`。
- [ ] `powershellscripts-ops` 文档说明全局触发时应如何定位并进入本仓库根目录。
- [ ] 安装器 dry-run 能展示 `powershellscripts-ops` 的 global 安装计划，且不影响其他已配置 skill。
- [ ] skill 校验通过。
- [ ] 仓库中不再存在会误导维护者修改 `.agents/skills/repo-ops` 的活动引用。
- [ ] 相关变更通过项目要求的校验；如果只改文档，可按规则跳过 `pnpm qa`，否则执行根目录 `pnpm qa`，涉及 PowerShell 安装器逻辑时还要执行 PowerShell 测试。

## Decisions

- 全局安装态仓库定位规则采用 `POWERSHELLSCRIPTS_REPO` 环境变量优先，未设置时兜底到 `/Users/mudssky/projects/env/powershellScripts`。
- 全局 skill 名称采用 `powershellscripts-ops`，避免 `repo-ops` 在用户级全局列表中过泛。
- `powershellscripts-ops` 是唯一迁移和安装目标；不新增安装辅助 skill，不安装 Trellis skill。
- 不暴露 project scope 安装作为推荐路径，避免同一 skill 在 global 和 project 中重复。

## Out of Scope

- 不重写 `skills` CLI。
- 不把真实 token、私有配置或机器专属 secret 写入 skill。
- 不安装 Trellis skill。
- 不把所有实验性 `ai/skills/dev/*` 都安装到全局。
- 不把 `.agents/skills/repo-ops` 保留为第二份需要同步维护的副本。
- 不推荐把该 skill 额外安装到 project scope。
- 不在规划阶段直接修改用户全局 skill 目录；实现阶段如需真实安装，应先走 dry-run 或明确命令。

## Open Questions

- 暂无阻塞规划的问题。实现前需要用户确认当前 `design.md` 与 `implement.md`。
