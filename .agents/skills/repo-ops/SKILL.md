---
name: repo-ops
description: 管理 powershellScripts 仓库运维任务时使用，包括 LiteLLM 网关、LobeHub 自托管、项目依赖安装、Docker Compose 服务生命周期、日志状态排查、环境变量示例文件，以及维护本地 repo-ops skill。
---

# Repo Ops

## 使用场景

当用户要处理本仓库内的运维工作时使用本 skill，尤其是：

- LiteLLM 网关：模型路由、fallback、配置同步、启动、重启、日志、运行时 smoke test。
- LobeHub 自托管：external/internal 模式、服务启动、状态、日志、RustFS bucket 初始化和常见排查。
- 项目依赖安装：根目录初始化、PowerShell 模块、Node/Bash 工具构建、pnpm QA。
- 本 skill 维护：新增运维域、更新 reference、刷新 `agents/openai.yaml`、校验 skill 结构。

## 工作流

1. 先确认用户要处理的运维域，再只读取对应 reference。
2. 优先使用仓库已有脚本，不直接手写复杂 `docker compose` 参数。
3. 涉及 `.env`、`.env.local`、API key、数据库密码时，只引用变量名和示例文件，不输出真实值。
4. 修改配置后执行最小必要验证；如果操作依赖 Docker、上游额度、密钥或网络，明确说明验证边界。
5. 对代码或项目文件变更，遵守根目录质量规则：通常完成后运行 `pnpm qa`，pwsh 相关改动再按项目规则追加 PowerShell 测试。

## Reference 选择

- LiteLLM 网关任务：读取 `references/litellm.md`。
- LobeHub 自托管任务：读取 `references/lobehub.md`。
- 项目安装、依赖、QA：读取 `references/project-install.md`。
- 修改本 skill 或新增运维域：读取 `references/skill-maintenance.md`。

## 操作边界

- 不把真实 secret 写入 skill、任务文档、提交信息或最终答复。
- 不默认停止、删除 volume、迁移数据或执行破坏性 Docker 操作；这类操作需要用户明确要求。
- 不把 LiteLLM 的 OpenAI 兼容 `claw-` 路由和 Claude Code Anthropic messages 兜底路由混用。
- 不把 LobeHub external 模式误认为项目会启动 PostgreSQL、Redis、RustFS；默认 external 依赖宿主机共享服务。
