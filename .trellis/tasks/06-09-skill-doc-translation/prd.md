# brainstorm: 中文技术文档翻译 skill

## Goal

创建一个用于中文技术文档翻译的 agent skill，让 AI 在翻译 README、规范、PRD、技术文档、运维说明、注释性 Markdown 时，能做语境合适、结构安全、术语一致的翻译，而不是逐字直译。第一版默认面向“外文技术文档 -> 简体中文”，用户明确指定目标语言时可支持其他方向。重点不是泛用翻译，而是让译文符合技术文档规范：结构清晰、术语稳定、步骤可执行、示例和正文一致。

## What I Already Know

- 用户要求开发一个中文技术文档翻译 skill，目标是“能对文档合适的翻译”。
- 用户确认默认按推荐方向收敛：外文技术文档翻译成简体中文；用户明确指定目标语言时可支持其他方向。
- 用户强调重点是“技术文档的规范”，skill 需要在翻译时同步检查文档结构、术语、示例和可执行步骤。
- 用户指定 skill 放在 `ai/skills/dev` 目录。
- 当前仓库已有 `ai/skills/dev/<skill-name>/SKILL.md` 规范，`pnpm-workspace.yaml` 已包含 `ai/skills/dev/*`。
- `ai/skills/SKILL_SPEC.md` 明确纯文档型 skill 推荐结构为 `ai/skills/dev/<skill-name>/SKILL.md`，可按需添加 `references/` 和 `examples/`。
- 当前仓库已有开发类 skills，例如：
  - `ai/skills/dev/api-example-test-writer/SKILL.md`
  - `ai/skills/dev/browser-bookmark-organizer/SKILL.md`
- `ai/skills/Install-Skills.ps1 -IncludeDevAll` 会发现 `dev/*/SKILL.md`。
- AGENTS 约束：创建 skill 时，Markdown 文档主要内容使用中文。
- 已读取 skill 创建规范：
  - `ai/skills/SKILL_SPEC.md`
  - `/Users/mudssky/.agents/skills/write-a-skill/SKILL.md`
  - `/Users/mudssky/.codex/skills/.system/skill-creator/SKILL.md`
- 本任务为纯文档型 skill，预计不需要脚本或单元测试；后续实现前应读取 `.trellis/spec/infra/agent-skill-dev.md`。
- 仓库没有统一的通用技术文档写作规范文件；已有文档和计划反复要求 README、CLI help、示例、配置字段和测试断言保持一致。

## Assumptions

- Skill 名称使用 `doc-translation`。
- 最终路径使用 `ai/skills/dev/doc-translation/SKILL.md`，既满足用户指定目录，又符合仓库现有 skill 结构。
- 第一版只写 `SKILL.md`，不加脚本；翻译判断主要依赖 agent 语言能力和明确流程。
- 默认面向技术/运维/项目文档翻译，特别是 Markdown、Trellis spec、README、PRD、Compose/CLI 文档。
- 默认输出完整译文，保留原文 Markdown 结构；只有用户要求审校、术语确认或逐段校对时，才输出原文+译文对照。
- `references/` 和 `examples/` 暂不创建；如果 `SKILL.md` 内容明显过长，再拆分。

## Requirements

- Skill frontmatter 必须包含明确 `name` 和 `description`，能触发技术文档翻译场景。
- `name` 必须为 `doc-translation`，并与目录名一致。
- Skill 正文主要使用中文。
- 默认翻译方向为外文技术文档到简体中文；用户明确指定目标语言时再切换。
- 翻译前应识别文档类型、目标语言、受众、是否需要保留原文术语，以及是否需要对表达做本地化调整。
- 翻译前应识别技术文档角色：教程、README、API/CLI 参考、运维 runbook、规范、PRD、变更说明或故障排查，并按文档角色调整译文结构。
- 翻译时必须保留 Markdown 结构、标题层级、表格、列表、链接、代码块、inline code、命令、路径、env key、API 字段、配置键、错误码和版本号。
- 翻译时应维护技术文档规范：标题层级清晰，步骤有前置条件、操作、预期结果或验证方式；命令示例、配置字段、参数名和正文描述必须一致。
- 对 CLI/API/配置文档，必须优先保证可执行性和契约准确性，不为了中文流畅改写命令、字段、状态码或返回结构。
- 技术术语、产品名、命令、变量、错误码等应采用“保留原文或中英混排”的策略，并在同一文档内保持一致。
- 翻译应优先语义自然和面向目标读者，而不是机械逐字翻译。
- 对不确定术语应保持一致，并可在输出后给出简短术语说明或待确认项。
- Skill 不默认联网；只有用户要求查官方术语、当前资料或库/API 文档时，才按现有文档检索规则执行。

## Acceptance Criteria

- [ ] 创建 `ai/skills/dev/doc-translation/SKILL.md`。
- [ ] `SKILL.md` frontmatter 包含 `name: doc-translation` 和具体 `description`。
- [ ] `description` 明确说明触发场景，例如翻译 README、Markdown、技术文档、规范、PRD、运维文档、CLI/API 文档。
- [ ] Skill 正文包含使用时机、翻译流程、保留内容规则、术语处理规则、质量检查和边界说明。
- [ ] Skill 正文包含技术文档规范检查规则，例如结构层级、步骤可执行性、示例一致性、CLI/API/配置契约保真。
- [ ] Skill 正文主要为中文，且示例覆盖 Markdown 文档和技术配置片段。
- [ ] Skill 明确默认翻译方向为外文技术文档到简体中文，用户指定时可切换目标语言。
- [ ] Skill 明确默认输出完整译文；用户要求审校或逐段核对时才输出原文+译文对照。
- [ ] Skill 明确不默认联网；只有用户要求查证术语或当前资料时才进行文档检索。
- [ ] 运行结构或安装发现验证，例如 `pwsh -NoProfile -File ./ai/skills/Install-Skills.ps1 -IncludeDevAll -DryRun`，或说明未运行原因。

## Definition of Done

- 纯 skill 文档通常不需要单元测试。
- 按仓库规则执行根目录 `pnpm qa`；如果只修改文案且确认无需 QA，在总结中说明。
- 如果改动范围仅为 Markdown 文档，不需要 PowerShell 全量测试。
- 变更可按 Conventional Commits 提交，建议提交信息：`feat(skill): 新增中文技术文档翻译 skill`。

## Out of Scope

- 第一版不实现机器翻译 API 调用脚本。
- 第一版不自动批量改写整个仓库文档。
- 第一版不承诺法律、医学、合同等高风险专业翻译质量。
- 第一版不替代人工审校；可提供“需要人工确认”的术语或句子。
- 第一版不创建多平台专属 skill 副本；先放在 `ai/skills/dev`。

## Technical Notes

- 最终路径：`ai/skills/dev/doc-translation/SKILL.md`。
- 纯文档型 skill 的 `SKILL.md` 是唯一必需文件；当前需求预计单文件足够。
- `SKILL.md` frontmatter description 是触发依据，必须具体，避免“帮翻译”这种过宽描述。
- 后续实现前读取：
  - `ai/skills/SKILL_SPEC.md`
  - `.trellis/spec/infra/agent-skill-dev.md`
  - 现有 `ai/skills/dev/*/SKILL.md` 示例
