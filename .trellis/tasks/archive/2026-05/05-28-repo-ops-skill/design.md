# Repository ops skill design

## Skill Structure

```text
.agents/skills/repo-ops/
├── SKILL.md
├── agents/
│   └── openai.yaml
└── references/
    ├── litellm.md
    ├── lobehub.md
    ├── project-install.md
    └── skill-maintenance.md
```

## Design Decisions

- `repo-ops` 是短名称，适合作为本仓库内部共享运维入口；frontmatter description 负责包含 LiteLLM、LobeHub、依赖安装等关键词。
- `SKILL.md` 只保留通用操作纪律：先识别域、读取对应 reference、避免泄漏 secrets、优先使用仓库脚本、操作后做轻量验证。
- `references/litellm.md` 保存 LiteLLM 的目录、配置、命令、模型路由与验证提示。LiteLLM 细节较多，单独拆分能避免其它运维任务加载无关上下文。
- `references/lobehub.md` 保存 LobeHub external/internal 模式、常用 Docker Compose 操作和 RustFS 注意事项。
- `references/project-install.md` 保存根目录安装依赖、PowerShell 模块、pnpm scripts 和 QA 边界。
- `references/skill-maintenance.md` 保存后续扩展或修订该 skill 时的流程，避免维护说明散落在额外 README 中。

## Validation

- 使用 skill-creator 自带 `quick_validate.py` 验证 skill 结构。
- 运行根目录 `pnpm qa`。本任务主要是 Markdown 和 skill 元数据，但按项目规则，代码改动任务完成时仍执行 QA；若 QA 与环境依赖冲突，记录具体失败点。
