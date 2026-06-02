# Research: LiteLLM retry and fallback for 429

- Query: LiteLLM Proxy/Router 在上游 429 / RateLimitError 时如何重试、fallback、cooldown，以及本仓库 `ai/gateway/litellm/litellm.local.yaml` 应如何配置以尽量不把瞬时 429 暴露给前端客户端。
- Scope: mixed
- Date: 2026-05-07

## Findings

### Files found

- `ai/gateway/litellm/litellm.local.yaml`: 当前 LiteLLM 本地默认配置，包含 Claude Code GLM 主入口、DeepSeek 兜底、全局 retry、Router fallback 与 cooldown。
- `ai/gateway/litellm/newapi.yaml`: 旧/备用 NewAPI 配置，已有 `litellm_settings.num_retries` 与 `router_settings.num_retries`，但没有 Claude Code GLM fallback。
- `ai/gateway/litellm/qwen.yaml`: 小型 fallback 示例，展示主模型、备用模型、`router_settings.fallbacks`、`allowed_fails`、`cooldown_time`、`num_retries` 的组合。
- `ai/gateway/litellm/litellm.md`: 用户文档，已说明 Claude Code GLM 优先、DeepSeek 兜底和 cooldown 恢复探测语义。
- `ai/gateway/litellm/docs/multi-newapi-routing.md`: 多 NewAPI 路由方案文档，其中方案 D 说明同模型多上游主备/fallback。
- `ai/gateway/litellm/compose.yaml`: LiteLLM 容器入口；镜像目前使用 `${LITELLM_IMAGE:-docker.litellm.ai/berriai/litellm:main-latest}`，行为随 `main-latest` 漂移。
- `.trellis/tasks/05-07-litellm-fallback-retry-429/prd.md`: 当前任务 PRD，目标是让 429 先由网关 retry/fallback 吸收，失败边界仍可暴露给客户端。
- `.trellis/spec/node-script/frontend/index.md`: 当前任务包索引；该索引是 frontend 占位规范，本任务主要改 YAML/文档，没有发现更精确的 LiteLLM 配置规范。

### Code patterns

- `ai/gateway/litellm/litellm.local.yaml:45`: `cc-glmplan-opus` 是 Claude Code 主入口，实际上游为智谱 Anthropic 兼容端点。
- `ai/gateway/litellm/litellm.local.yaml:52`: `cc-glmplan-opus` 配置了 `cooldown_time: 3600`，失败后该部署冷却 1 小时。
- `ai/gateway/litellm/litellm.local.yaml:55`: `cc-glmplan-haiku` 复用同一智谱 Anthropic 兼容入口。
- `ai/gateway/litellm/litellm.local.yaml:62`: `cc-glmplan-haiku` 同样配置了 `cooldown_time: 3600`。
- `ai/gateway/litellm/litellm.local.yaml:64`: `claude-code-deepseek-v4-pro` 是 GLM 主入口失败后的 pro 兜底部署。
- `ai/gateway/litellm/litellm.local.yaml:72`: `claude-code-deepseek-v4-flash` 是 Haiku/subagent 流量的轻量兜底部署。
- `ai/gateway/litellm/litellm.local.yaml:116`: `litellm_settings` 里已有 `num_retries: 2` 和 `request_timeout: 60`。
- `ai/gateway/litellm/litellm.local.yaml:126`: `router_settings` 开启 `enable_pre_call_checks`，并定义 Router 层行为。
- `ai/gateway/litellm/litellm.local.yaml:130`: 当前 `fallbacks` 只覆盖 `cc-glmplan-opus -> claude-code-deepseek-v4-pro` 与 `cc-glmplan-haiku -> claude-code-deepseek-v4-flash`。
- `ai/gateway/litellm/litellm.local.yaml:136`: `allowed_fails: 1` 让部署连续一次失败即进入 cooldown。
- `ai/gateway/litellm/litellm.local.yaml:138`: `router_settings.num_retries: 2` 与 SDK 层重试次数保持一致。
- `ai/gateway/litellm/qwen.yaml:21`: Qwen 示例在 `litellm_settings` 中设置 `num_retries: 2` 和 `request_timeout: 25`。
- `ai/gateway/litellm/qwen.yaml:28`: Qwen 示例用 `router_settings.fallbacks` 声明主模型失败后切到备用模型。
- `ai/gateway/litellm/qwen.yaml:36`: Qwen 示例用 `allowed_fails` 与 `cooldown_time` 避免故障上游持续接流量。
- `ai/gateway/litellm/litellm.md:181`: 文档已写明 `cc-glmplan-opus` 失败后降级到 DeepSeek pro。
- `ai/gateway/litellm/litellm.md:183`: 文档已说明 GLM 入口 cooldown 1 小时，冷却结束后下一次请求重新尝试 GLM。
- `ai/gateway/litellm/docs/multi-newapi-routing.md:193`: 方案 D 将“同模型多 NewAPI 主备 / 容灾”定义为解决单上游波动或限流的推荐模式。
- `ai/gateway/litellm/docs/multi-newapi-routing.md:227`: 方案 D 示例使用 `router_settings.fallbacks` 加 `num_retries: 2`。
- `ai/gateway/litellm/compose.yaml:4`: 当前 LiteLLM 镜像未 pin 版本，默认跟随 `main-latest`。

### External references

- LiteLLM Routing / Router docs: Router 基础可靠性覆盖 cooldown、fallback、timeout、retry。`order` 可以用于同一 `model_name` 下的主备部署；上游失败包含 404、429 等时，会先尝试下一 `order`，每个 order 层有自己的 retry，所有 order 耗尽后才进入已配置 fallback。参考：<https://docs.litellm.ai/docs/routing>
- LiteLLM Routing / Cooldowns docs: cooldown 作用在单个 deployment，而不是整个 model group。文档列出 429 rate limit 会触发 cooldown，默认 cooldown 为 5 秒；也可以全局或按模型设置 `cooldown_time`。参考：<https://docs.litellm.ai/docs/routing>
- LiteLLM Routing / Retries docs: Router 对失败请求支持 retry；对 `RateLimitError` 使用 exponential backoff，普通错误立即重试；`retry_after` 可设置 retry 前最小等待时间。参考：<https://docs.litellm.ai/docs/routing>
- LiteLLM Routing / Advanced retry policy docs: `router_settings.retry_policy` 可以按异常类型配置重试次数，例如 `RateLimitErrorRetries`；`allowed_fails_policy` 可以按异常类型配置进入 cooldown 前允许的失败次数，例如 `RateLimitErrorAllowedFails`。参考：<https://docs.litellm.ai/docs/routing>
- LiteLLM Fallbacks docs: fallback 发生在某个调用 `num_retries` 后仍失败时，通常从一个 `model_name` 切到另一个 `model_name`；普通 `fallbacks` 覆盖剩余错误，包括 `litellm.RateLimitError`。参考：<https://docs.litellm.ai/docs/proxy/reliability>
- LiteLLM Fallbacks advanced docs: 文档明确 fallback + retry + timeout + cooldown 配置覆盖 429、500 等错误，并示例 `num_retries` 是每个 `model_name` 上的 retry 次数，fallback 在 retry 后触发。参考：<https://docs.litellm.ai/docs/proxy/reliability>
- LiteLLM All settings docs: `router_settings` 与 `litellm_settings` 有重叠时，`router_settings` 覆盖 `litellm_settings`；`router_settings` 支持 `retry_policy`、`allowed_fails_policy`、`fallbacks`、`num_retries`、`max_fallbacks`、`retry_after` 等字段。参考：<https://docs.litellm.ai/docs/proxy/config_settings>

### Interpretation for this task

- 对当前 Claude Code GLM 两个入口来说，已有 `router_settings.fallbacks` 理论上已经覆盖 429，因为 LiteLLM 文档将 429 归入普通 fallback 覆盖范围，并明确普通 `fallbacks` 包含 `RateLimitError`。
- 当前 `router_settings.num_retries: 2` 表示 GLM 主入口会先在当前模型组内重试；重试仍失败后，才会进入 `cc-glmplan-opus -> claude-code-deepseek-v4-pro` 或 `cc-glmplan-haiku -> claude-code-deepseek-v4-flash`。
- 当前 `allowed_fails: 1` 加 GLM 部署上的 `cooldown_time: 3600` 会让 GLM 在一次失败后冷却 1 小时。若 429 代表 Coding Plan 额度耗尽，这个策略合理；若 429 只是短时 RPM 抖动，1 小时可能过长。
- 如果目标只是让 Claude Code GLM 入口的 429 尽量不透给客户端，最小实现通常是保留现有 fallback，并补充显式 `retry_policy.RateLimitErrorRetries`、必要时补充 `retry_after` 注释、更新文档说明边界。
- 如果目标扩展到 `gpt-5.5`、`gemini-3.1-pro`、`compat/claude-*`、`GLM-*`、`*` 等其它模型，目前还没有对应备用 `model_name` 或备用 deployment；单靠 `num_retries` 只能重试同一上游，不能把持续 429 转到另一个供应商。
- 对同一个外部模型名需要多上游容灾时，LiteLLM 官方 `order` 模式可能比显式 fallback 更自然：多个 deployment 共享同一 `model_name`，主 deployment 设置 `order: 1`，备 deployment 设置 `order: 2`，客户端模型名不变，Router 在 429 等失败后尝试下一 order。
- 对跨模型降级，比如 GLM 失败切 DeepSeek，当前的 `router_settings.fallbacks` 更合适，因为这是从一个业务入口切到另一个内部备用 `model_name`。

### Recommended implementation direction

- 保持主入口和兜底模型名不变，避免改客户端配置。
- 在 `router_settings` 下显式加入或确认：
  - `num_retries: 2`：保留短重试，避免瞬时 429 直接 fallback。
  - `retry_policy.RateLimitErrorRetries: 2`：让 429 语义显式，不依赖读者理解 `num_retries` 对所有错误生效。
  - `fallbacks`：保留当前两条 Claude Code GLM 到 DeepSeek 的 fallback。
  - `allowed_fails: 1` 与 GLM deployment `cooldown_time: 3600`：保留或按“额度耗尽 vs 短时限流”的产品判断调整。
- 如果要降低交互延迟，不要盲目提高 `num_retries`；对前端/Claude Code 这类交互式调用，更可靠的策略通常是短重试后尽快 fallback。
- 如果要保护其它显式模型的 429，需要先新增备用 model/deployment，再为这些 model group 增加 `fallbacks` 或 `order`，否则没有可切换的健康目标。

## Caveats / Not Found

- 未发现仓库内有 LiteLLM 429 retry/fallback 的自动化集成测试；官方文档提供 `mock_testing_fallbacks=true` 测试普通 fallback，但这不完全等价于真实上游 429。
- 当前 compose 默认使用 `main-latest` 镜像，未 pin LiteLLM 版本；研究结论基于 2026-05-07 官方在线文档，实际运行行为可能随镜像更新变化。
- 官方 config settings 文档提到 `retry_after` 默认 0，并说收到 `x-retry-after` 时会覆盖；未在本轮验证标准 `Retry-After` 响应头是否同样被当前镜像尊重。
- fallback 只能隐藏“重试或备用模型最终成功”的 429；如果主模型和所有备用模型都限流、认证失败、额度耗尽或不可用，错误仍会返回客户端。
- streaming 请求在已经向客户端发送部分 token 后，任何网关都很难无感切换到备用模型；本轮未验证 LiteLLM 当前镜像对 streaming 429 的 retry/fallback 行为。
- `.trellis/spec/node-script/frontend/index.md` 是占位型 frontend 规范，未提供 LiteLLM YAML 配置专用约束；本任务更应以现有 `ai/gateway/litellm` 文件模式和官方 LiteLLM 文档为准。
