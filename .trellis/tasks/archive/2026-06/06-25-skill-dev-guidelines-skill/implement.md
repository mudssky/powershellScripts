# 创建 skill 开发规范 skill - Implement

## Checklist

1. 进入实现前加载 `trellis-before-dev`，读取 infra skill 开发规范。
2. 创建 `ai/skills/dev/skill-dev-guidelines/` 目录和 `references/`。
3. 编写 `SKILL.md`：
   - frontmatter `name: skill-dev-guidelines`
   - description 明确触发“本仓库 ai/skills/dev 本地 skill 开发、Python/TypeScript 脚本型 skill、目录结构检查、验证流程”
   - 正文使用中文，保持精简导航。
4. 编写 `references/general.md`、`references/python.md`、`references/typescript.md`。
5. 检查内容是否与 `ai/skills/SKILL_SPEC.md` 和 `.trellis/spec/infra/agent-skill-dev.md` 一致。
6. 运行基础校验：
   - skill frontmatter / 目录结构校验。
   - 根目录 `pnpm qa`，如果判定为纯文档改动且跳过，必须在最终说明原因。
7. 查看 `git diff`，确认只新增新 skill 和 Trellis 任务文档，不触碰 `powershellscripts-ops` 改动。

## Validation Commands

```bash
uv run --with pyyaml python C:/Users/mudssky/.codex/skills/.system/skill-creator/scripts/quick_validate.py ai/skills/dev/skill-dev-guidelines
pnpm qa
```

如果系统 skill-creator 路径不可用，先定位当前可用的 `quick_validate.py`，不要改写校验目标。若 `pnpm qa` 因仅文档改动选择跳过，最终说明依据项目规则“只修改文档说明可不执行 qa”。

## Rollback Points

- 新增目录 `ai/skills/dev/skill-dev-guidelines/` 可整体删除回滚。
- Trellis 任务文档只属于本任务，不影响运行时。

## Review Gate

用户确认 `prd.md`、`design.md`、`implement.md` 后，执行 `python ./.trellis/scripts/task.py start 06-25-skill-dev-guidelines-skill` 进入实现。
