# LiteLLM claw OpenAI fallback

## Goal

为 Hermes 等 OpenAI 兼容 agent 增加独立的 LiteLLM `claw-` 前缀模型入口，使其默认优先使用智谱 Coding Plan 的 `GLM-5.1` OpenAI 兼容端点，并在 GLM 额度耗尽或临时不可用时 fallback 到 DeepSeek 的 OpenAI 兼容端点。

该入口需要与现有 Claude Code 专用 `cc-glmplan-*` / `claude-code-deepseek-*` Anthropic messages 路由隔离，避免 OpenAI 兼容 agent 继承 Claude Code thinking sanitizer、Anthropic provider 或模型命名语义。

## Confirmed Facts

- `ai/gateway/litellm/litellm.local.yaml` 中 `model: "openai/GLM-5.1"` 已显式使用 LiteLLM OpenAI provider；这类配置适合转发到 OpenAI 兼容上游。
- LiteLLM 文档确认 OpenAI-compatible endpoint 需要使用 `openai/<model>` 前缀，并配置 `api_base` 与 `api_key`。
- DeepSeek 文档确认 DeepSeek API 兼容 OpenAI ChatCompletions，V4-Flash 的模型 id 为 `deepseek-v4-flash`，常规 OpenAI 兼容调用路径可使用 `https://api.deepseek.com/v1/chat/completions`。
- DeepSeek 文档显示旧模型名 `deepseek-chat` 与 `deepseek-reasoner` 将于 2026-07-24 停用，因此新路由不应使用旧模型名。
- 当前仓库已有 Claude Code 专用 GLM 路由：
  - `cc-glmplan-opus` / `cc-glmplan-haiku` -> `anthropic/GLM-5.1`
  - `claude-code-deepseek-v4-pro` / `claude-code-deepseek-v4-flash` -> DeepSeek Anthropic 兼容端点
- `.trellis/spec/infra/litellm-gateway.md` 明确 `cc-*` / `claude-code-deepseek-*` 是 Claude Code Anthropic messages 专用链路，包含 DeepSeek thinking sanitizer 和 GLM cooldown adapter 约束。
- 当前 `compose.yaml` 已注入 `Z_AI_CODING_API_BASE`、`Z_AI_ANTHROPIC_API_BASE`、`DEEPSEEK_ANTHROPIC_API_BASE`，但未发现 DeepSeek OpenAI 兼容端点专用环境变量；`.env.example` 与 `.env.production.example` 也需要补齐示例。
- 仓库未发现现成 `hermes` 或 `claw` 模型命名约定。
- 现有 `compat/claude-*` 别名做法是多个对外 `model_name` 分别直接映射到真实 provider 参数，而不是让一个 LiteLLM 对外别名再指向另一个 LiteLLM 对外别名。
- `ai/gateway/litellm/newapi.yaml` 与 `ai/gateway/litellm/litellm.local.yaml` 当前保留同构模型路由，新增 `claw-` 路由时需要同步更新两份文件。
- Hermes 配置尚未创建，本次不写入或生成 Hermes 侧配置文件。

## Requirements

- 新增面向 OpenAI 兼容 agent 的 `claw-` 前缀模型入口：
  - `claw-plan` 作为 Hermes 等 agent 推荐使用的稳定默认入口。
  - `claw-glmplan-5.1` 作为显式表达当前底层 GLM 版本的入口。
- `claw-plan` 与 `claw-glmplan-5.1` 默认都路由到智谱 Coding Plan `GLM-5.1` OpenAI 兼容端点。
- `claw-plan` 不应通过链式别名指向 `claw-glmplan-5.1`；两者应直接复用同一组 `litellm_params` 锚点或等价配置，减少 LiteLLM Router 分组与 fallback 语义的不确定性。
- `claw-` fallback 入口使用 DeepSeek OpenAI 兼容端点，不复用现有 DeepSeek Anthropic 兼容端点；fallback 模型采用 v4 flash 方向，对外命名为 `claw-deepseek-v4-flash`，底层模型名为 `openai/deepseek-v4-flash`，并默认开启最大思考模式。
- `claw-` 路由不得影响现有 `GLM-5.1`、`GLM-*`、`*`、`cc-glmplan-*` 与 `claude-code-deepseek-*` 路由行为。
- 配置需要通过环境变量注入 DeepSeek OpenAI 兼容 `api_base` 与密钥，避免硬编码私密值。
- 文档需要说明 Hermes / OpenAI 兼容 agent 未来应使用哪个模型名、哪个 LiteLLM Base URL、哪个鉴权 key，以及 fallback 语义。
- `litellm.local.yaml` 与 `newapi.yaml` 必须同步新增同一组 `claw-` 路由与 fallback 规则。

## Acceptance Criteria

- [x] `litellm.local.yaml` 暴露 `claw-plan`、`claw-glmplan-5.1` 与 DeepSeek OpenAI fallback 入口。
- [x] `newapi.yaml` 同步暴露 `claw-plan`、`claw-glmplan-5.1` 与 DeepSeek OpenAI fallback 入口。
- [x] `router_settings.fallbacks` 中存在 `claw-plan` 与 `claw-glmplan-5.1` 到 DeepSeek OpenAI fallback 入口的降级规则。
- [x] DeepSeek OpenAI fallback 对外模型名为 `claw-deepseek-v4-flash`。
- [x] `claw-deepseek-v4-flash` 默认传递最大思考强度，例如 `reasoning_effort: "max"`。
- [x] `compose.yaml` 注入 `claw-` fallback 所需的 `DEEPSEEK_OPENAI_API_BASE`，默认值为 `https://api.deepseek.com/v1`。
- [x] `.env.example` 与 `.env.production.example` 包含 `DEEPSEEK_OPENAI_API_BASE` 示例。
- [x] 相关文档说明 `claw-` 路由用途、模型名、环境变量和验证方式。
- [x] 配置解析通过项目现有 YAML 读取方式。
- [x] 根目录 `pnpm qa` 通过，或记录无法执行的具体原因。

## Out of Scope

- 不修改 Claude Code `cc-*` Anthropic messages 路由的 thinking / sanitizer 行为。
- 不引入新的 LiteLLM callback adapter，除非后续证据表明 OpenAI 兼容 fallback 需要请求体清洗。
- 不更改 Codex 直连 `z.ai` provider 配置。
- 不创建或更新 Hermes agent 配置文件。
- 不要求真实触发上游 429 才算完成；真实额度与供应商行为依赖本地密钥和实时状态。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
