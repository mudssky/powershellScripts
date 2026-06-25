# 创建 skill 开发规范 skill

## Goal

在 `ai/skills/dev` 下创建一个用于开发本仓库本地 agent skill 的规范型 skill。它应帮助后续 agent 在新增或维护 skill 时快速选择纯文档、Python 脚本型或 TypeScript 脚本型结构，并遵守安装态入口、依赖声明、测试与仓库 QA 约定。

## User Value

- 减少每次开发 `ai/skills/dev/<skill-name>/` 时重复翻找 `ai/skills/SKILL_SPEC.md` 与 `.trellis/spec/infra/agent-skill-dev.md` 的成本。
- 把 Python 与 TypeScript 两类脚本型 skill 的关键差异做成可触发、可导航、可执行的 agent 指引。
- 让后续 skill 开发默认遵守仓库现有结构和验证流程，避免安装态不可运行、依赖重复声明、生成产物遗漏等问题。

## Confirmed Facts

- 本仓库的本地开发 skill 位于 `ai/skills/dev/<skill-name>/`。
- `ai/skills/SKILL_SPEC.md` 已记录通用 skill 开发规范，包括纯文档、TypeScript 脚本型、轻量 Python 脚本和依赖型 Python/uv 项目的结构。
- `.trellis/spec/infra/agent-skill-dev.md` 已记录更细的可执行契约，包括 TypeScript、Python 和本地临时 WebUI 三个场景。
- `pnpm-workspace.yaml` 已包含 `ai/skills/dev/*`，TypeScript skill 可作为 workspace 包使用根目录 `typescript`、`vitest`、`biome` 等工具。
- 现有 TypeScript 脚本型 skill 示例包括 `ai/skills/dev/database-query` 与 `ai/skills/dev/project-launcher`。
- 现有 Python/uv 项目型 skill 示例包括 `ai/skills/dev/browser-bookmark-organizer`。
- `ai/skills/dev/powershellscripts-ops` 当前有用户未提交改动，本任务不得触碰或回滚这些改动。
- 按项目规则，代码改动任务完成时通常执行根目录 `pnpm qa`；如果只修改文档说明可不执行。

## Requirements

- 新增的 skill 必须放在 `ai/skills/dev` 下，目录名与 frontmatter `name` 保持一致。
- 新 skill 的 Markdown 主体内容使用中文。
- 新 skill 必须能在用户提出“创建/维护本仓库本地 skill”“开发 Python/TypeScript 脚本型 skill”“检查 skill 目录结构/验证命令”等请求时触发。
- `SKILL.md` 应保持精简，只放使用时机、核心工作流、语言路线选择、验证入口和 reference 导航。
- 详细规范应按需拆到 `references/`，至少覆盖：
  - 通用 skill 结构、frontmatter、progressive disclosure、安装同步与 `agents/openai.yaml` 边界。
  - Python skill 开发规范，包括轻量标准库脚本、依赖型 uv 项目、配置文件、测试和 smoke 验证。
  - TypeScript skill 开发规范，包括源码/测试/构建产物分层、`scripts/*.js` 安装态入口、根目录工具复用和测试验证。
- 新 skill 应明确复用仓库现有规范来源：`ai/skills/SKILL_SPEC.md` 与 `.trellis/spec/infra/agent-skill-dev.md`，不要复制成失控的第二套规范。
- 新 skill 应提醒开发者遵守用户规则：函数/公共接口注释要说明功能、入参、返回值；复杂设计意图用中文注释，不重复基础语法。
- 新 skill 不应实现新的 CLI、脚手架或自动生成器，除非后续用户明确扩展范围。
- 新 skill 不应修改现有 skill 的业务逻辑、安装器或 `powershellscripts-ops` 当前改动。
- 首版范围限定为“开发规范、检查清单、Python/TypeScript 路线选择和按需 reference 导航”，不包含脚手架 CLI 或默认安装配置变更。
- 新 skill 目录名暂定为 `skill-dev-guidelines`。

## Acceptance Criteria

- [ ] `ai/skills/dev/<new-skill-name>/SKILL.md` 存在，frontmatter 合法，`name` 与目录名一致，description 具备明确触发条件。
- [ ] 新 skill 包含按需读取的 reference 文件，能分别指导通用、Python、TypeScript 三类 skill 开发。
- [ ] 内容与 `ai/skills/SKILL_SPEC.md`、`.trellis/spec/infra/agent-skill-dev.md` 的现有契约一致，不引入冲突规则。
- [ ] 不触碰用户已有 `powershellscripts-ops` 工作区改动。
- [ ] 运行 skill 基础校验；如果仅新增 Markdown 文档，可说明未运行 `pnpm qa` 的原因，或按需执行 `pnpm qa`。
- [ ] Trellis planning artifacts 经用户确认后再进入实现。

## Out of Scope

- 不创建 Python/TypeScript 脚手架 CLI。
- 不改造 `ai/skills/Install-Skills.ps1` 或 `skills.config.json` 的安装行为，除非用户后续明确要求把新 skill 纳入默认安装。
- 不重写或迁移已有 skill。
- 不把上游系统 `skill-creator` 的全部说明复制进本仓库。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
