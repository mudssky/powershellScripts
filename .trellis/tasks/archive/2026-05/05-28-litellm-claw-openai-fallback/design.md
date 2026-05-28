# LiteLLM claw OpenAI fallback Design

## Architecture and Boundaries

本变更在 `ai/gateway/litellm` 内新增一组 OpenAI 兼容 agent 专用模型路由，使用 `claw-` 前缀与现有 Claude Code Anthropic messages 路由隔离。

对外模型名分为三类：

- `claw-plan`：推荐给 Hermes 等 OpenAI 兼容 agent 使用的稳定默认入口。
- `claw-glmplan-5.1`：显式版本入口，便于调试时确认底层 GLM 版本。
- `claw-deepseek-v4-flash`：DeepSeek OpenAI 兼容 fallback 入口。

`claw-plan` 和 `claw-glmplan-5.1` 不做 LiteLLM alias 链式转发；两者都直接复用同一组智谱 OpenAI 兼容参数，底层为 `openai/GLM-5.1`。这样避免 Router fallback 依赖另一个对外模型名的二次解析，也与仓库现有 `compat/claude-*` 的别名模式一致。

## Data Flow and Contracts

OpenAI 兼容 agent 调用 `model=claw-plan` 时：

1. LiteLLM 命中 `claw-plan` 模型组。
2. 请求通过 `Z_AI_CODING_API_BASE` 转发到智谱 Coding Plan OpenAI 兼容端点。
3. 上游模型固定为 `GLM-5.1`。
4. 如果 GLM 请求在短重试后仍失败，Router fallback 到 `claw-deepseek-v4-flash`。
5. DeepSeek fallback 使用 `DEEPSEEK_OPENAI_API_BASE` 与 `DEEPSEEK_API_KEY`，底层模型为 `openai/deepseek-v4-flash`，并默认传递 `reasoning_effort: "max"` 以开启最大思考模式。

`claw-glmplan-5.1` 走同样链路，适合需要显式指定底层版本的客户端。

`claw-deepseek-v4-flash` 只作为 OpenAI 兼容 fallback 或手动诊断入口，不复用 `DEEPSEEK_ANTHROPIC_API_BASE`，也不进入 Claude Code thinking sanitizer 的语义边界。最大思考模式通过 OpenAI 兼容请求参数表达，不沿用 Claude Code 的 Anthropic `thinking` / `output_config` 合同。

## Compatibility and Migration Notes

- `cc-glmplan-*`、`claude-code-deepseek-*`、`GLM-5.1`、`GLM-*` 与全局 `*` 路由保持现有行为。
- `newapi.yaml` 与 `litellm.local.yaml` 保持同构新增，避免两个配置文件暴露不同模型契约。
- `compose.yaml` 新增 `DEEPSEEK_OPENAI_API_BASE` 白名单变量，默认 `https://api.deepseek.com/v1`。
- `.env.example` 与 `.env.production.example` 同步加入 `DEEPSEEK_OPENAI_API_BASE` 示例。
- 文档只说明 Hermes 未来应使用 `claw-plan`；不创建 Hermes 配置文件。
- DeepSeek 旧模型名 `deepseek-chat` / `deepseek-reasoner` 已有明确停用时间，不用于新路由。
- DeepSeek V4-Flash 的 OpenAI 兼容 fallback 默认使用 `reasoning_effort: "max"`，服务复杂 agent 场景；如果后续轻量任务需要非思考或低强度模式，应新增单独的 safe/light 路由。

## Trade-offs

- 同时暴露 `claw-plan` 与 `claw-glmplan-5.1` 会让 `/models` 多一个入口，但换来稳定默认入口和显式调试入口的分离。
- `claw-plan` 不链式指向 `claw-glmplan-5.1` 会重复一小段 YAML，但 Router 行为更直接，fallback 配置也更可读。
- 本次不新增 OpenAI 兼容路径的 callback 清洗逻辑；如果后续真实 agent 历史消息暴露跨供应商兼容问题，再新增独立 safe 路由或 adapter。

## Operational and Rollback Notes

- 部署后通过 `/models?return_wildcard_routes=true` 验证 `claw-plan`、`claw-glmplan-5.1`、`claw-deepseek-v4-flash` 可见。
- 修改配置后用 `start.ps1 apply` 重建 LiteLLM 容器使配置生效。
- 如需回滚，删除三条 `claw-` 模型、两条 fallback 规则和 `DEEPSEEK_OPENAI_API_BASE` 相关文档/环境示例即可；现有 Claude Code 与 GLM 路由不受影响。
