# Repository ops skill

## Goal

在本仓库 `.agents/skills/` 下创建项目级运维 skill，供后续 agent 处理仓库内常见运维任务时快速加载正确入口、约束和验证方式。

## Requirements

- Skill 名称采用 `repo-ops`，目录为 `.agents/skills/repo-ops/`。
- `SKILL.md` 主体内容使用中文，并保持精简，只负责触发范围、通用流程和 reference 路由。
- 初版覆盖以下运维域：
  - LiteLLM 网关：`ai/gateway/litellm/` 下启动、重启、应用配置、日志、模型路由、环境变量和运行时 smoke test。
  - LobeHub 自托管：`ai/self-hosted/lobehub/` 下 external/internal 模式、日志、状态、RustFS bucket 初始化和常见排查。
  - 项目依赖安装：根目录 `install.ps1`、`pnpm pwsh:install` / `pnpm scripts:install`、质量检查和 PowerShell 模块安装入口。
  - Skill 后续维护：新增/更新 reference、刷新 `agents/openai.yaml`、运行校验和避免敏感信息泄漏的流程。
- 详细命令和注意事项拆分到 `references/`，按任务需要渐进读取，避免 `SKILL.md` 过长。
- 不在 skill 中记录真实 `.env`、`.env.local`、API key、数据库密码等敏感值；只能引用示例文件和变量名。
- 与现有 Trellis/skill 规范保持一致，新增 skill 作为项目本地共享能力，不修改全局 Codex skill。

## Acceptance Criteria

- [x] `.agents/skills/repo-ops/SKILL.md` 存在，frontmatter 至少包含 `name` 和清晰的 `description`。
- [x] `.agents/skills/repo-ops/references/litellm.md` 覆盖 LiteLLM 常用操作、关键文件、环境变量边界和验证方式。
- [x] `.agents/skills/repo-ops/references/lobehub.md` 覆盖 LobeHub 常用操作、external/internal 模式和故障排查入口。
- [x] `.agents/skills/repo-ops/references/project-install.md` 覆盖项目初始化、依赖安装、PowerShell 模块和 QA 命令。
- [x] `.agents/skills/repo-ops/references/skill-maintenance.md` 覆盖后续更新该 skill 的维护流程。
- [x] Skill 校验脚本通过，或记录阻塞原因。
- [x] 根目录 `pnpm qa` 通过，或记录因环境导致无法完成的原因。

## Notes

- 已确认用户希望初版先收 LiteLLM、LobeHub 和项目安装依赖。
- 用户要求“创建 skill 时，md 文档主要内容使用中文”。
