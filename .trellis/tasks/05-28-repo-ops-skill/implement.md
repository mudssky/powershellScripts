# Repository ops skill implementation plan

## Steps

1. 使用 skill-creator 初始化 `.agents/skills/repo-ops/`，包含 `references/` 和 `agents/openai.yaml`。
2. 编写中文 `SKILL.md`，定义触发范围、通用流程、安全边界和 reference 选择规则。
3. 编写四份 reference：
   - `litellm.md`
   - `lobehub.md`
   - `project-install.md`
   - `skill-maintenance.md`
4. 运行 skill 校验。
5. 运行 `pnpm qa`。
6. 汇总变更和验证结果。
