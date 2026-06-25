# 创建 skill 开发规范 skill - Design

## Architecture

新增一个纯文档型 skill：

```text
ai/skills/dev/skill-dev-guidelines/
  SKILL.md
  references/
    general.md
    python.md
    typescript.md
```

`SKILL.md` 负责触发、工作流、路线选择和 reference 导航。三个 reference 文件按需加载，避免把 `ai/skills/SKILL_SPEC.md` 与 `.trellis/spec/infra/agent-skill-dev.md` 的全部细节堆进主文件。

## Content Boundaries

- `SKILL.md`：说明何时使用、先读哪些仓库规范、如何根据纯文档 / Python / TypeScript / WebUI 场景选择 reference，以及最终验证入口。
- `references/general.md`：记录通用结构、frontmatter、progressive disclosure、安装态边界、`agents/openai.yaml` 和安装同步注意事项。
- `references/python.md`：记录轻量标准库脚本与依赖型 uv 项目的选择规则、配置文件策略、测试和 smoke 验证。
- `references/typescript.md`：记录 TypeScript skill 的源码/测试/分发产物分层、根工具复用、构建产物提交和验证。

## Source Of Truth

新 skill 是操作导航层，不是第二套规范源。内容必须显式指向并服从：

- `ai/skills/SKILL_SPEC.md`
- `.trellis/spec/infra/agent-skill-dev.md`

如果发现两处源规范与新 skill 文案冲突，以源规范为准，并更新新 skill 文案。

## Compatibility

- 不修改 `ai/skills/Install-Skills.ps1` 或 `skills.config.json`，首版不纳入默认安装。
- 不依赖脚本、Node 包、Python 包或外部服务。
- 不触碰现有 `powershellscripts-ops` 未提交改动。

## Trade-offs

首版不做脚手架 CLI。好处是实现小、维护成本低、不会引入新的生成器契约；代价是创建新 skill 时仍需要 agent 手工建目录和文件。后续如果重复操作明显增多，再单独扩展脚手架。
