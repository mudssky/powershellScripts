# LiteLLM Gateway Spec

> 本规范记录 `ai/gateway/litellm` 的路由与跨供应商兼容约定。修改 LiteLLM 配置、Claude Code 网关入口或模型 fallback 时必须先阅读。

---

## Scenario: OpenAI 兼容 claw agent GLM Fallback 到 DeepSeek V4 Flash

### 1. Scope / Trigger

- Trigger: 修改 `ai/gateway/litellm/*.yaml` 中 `claw-` 模型入口、DeepSeek OpenAI 兼容兜底别名、`router_settings.fallbacks`、`DEEPSEEK_OPENAI_API_BASE` 注入或 LiteLLM OpenAI 兼容 agent 文档。
- Scope: `claw-plan` / `claw-glmplan-5.1` 优先使用智谱 GLM Coding Plan 的 OpenAI 兼容端点；GLM 短重试后仍失败时 fallback 到 `claw-deepseek-v4-flash`。
- Design intent: 为 Hermes 等 OpenAI 兼容 agent 提供稳定模型名，同时与 Claude Code Anthropic messages 链路隔离。

### 2. Signatures

- Client-facing model names:
  - `claw-plan`
  - `claw-glmplan-5.1`
  - `claw-deepseek-v4-flash`
- Provider model mapping:
  - `claw-plan` -> `openai/GLM-5.1`
  - `claw-glmplan-5.1` -> `openai/GLM-5.1`
  - `claw-deepseek-v4-flash` -> `openai/deepseek-v4-flash`
- Router fallback contract:
  - `claw-plan` -> `claw-deepseek-v4-flash`
  - `claw-glmplan-5.1` -> `claw-deepseek-v4-flash`

### 3. Contracts

- Required environment keys:
  - `Z_AI_CODING_API_BASE`: 智谱 GLM Coding Plan OpenAI 兼容端点。
  - `Z_AI_API_KEY`: 智谱 Coding Plan 密钥。
  - `DEEPSEEK_OPENAI_API_BASE`: DeepSeek OpenAI 兼容端点，默认 `https://api.deepseek.com/v1`。
  - `DEEPSEEK_API_KEY`: DeepSeek 密钥。
  - `LITELLM_MASTER_KEY`: LiteLLM 对外鉴权密钥。
- Naming policy:
  - `claw-plan` 是推荐给 agent 配置使用的稳定入口；底层 GLM 版本升级时优先保持该对外模型名不变。
  - `claw-glmplan-5.1` 是显式版本入口，必须直接映射到真实 provider 参数，不得通过 LiteLLM alias 链式转发到 `claw-plan` 或其它对外模型名。
  - `claw-deepseek-v4-flash` 是 OpenAI 兼容兜底入口，不得复用 `claude-code-deepseek-*` 的 Anthropic messages 语义。
- Parameter policy:
  - `claw-deepseek-v4-flash` 必须默认配置 `reasoning_effort: "max"`，用于复杂 agent 场景的最大思考模式。
  - `claw-` OpenAI 兼容链路不使用 Claude Code 的 `thinking` / `output_config.effort` 合同；不要为它新增 DeepSeek Anthropic sanitizer 依赖。
  - 不得使用 DeepSeek 旧模型名 `deepseek-chat` 或 `deepseek-reasoner` 创建新路由。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| GLM 正常可用 | `claw-plan` / `claw-glmplan-5.1` 直接走 `openai/GLM-5.1` |
| GLM 返回 429 / `RateLimitError` | LiteLLM 先按 retry policy 短重试 |
| GLM 短重试耗尽 | Router fallback 到 `claw-deepseek-v4-flash` |
| DeepSeek OpenAI fallback 被选中 | 请求走 `DEEPSEEK_OPENAI_API_BASE`，模型为 `deepseek-v4-flash`，默认 `reasoning_effort=max` |
| `DEEPSEEK_OPENAI_API_BASE` 未注入容器 | `claw-deepseek-v4-flash` 配置解析或运行时请求失败，应检查 compose 白名单和 `.env.local` |
| Claude Code fallback 触发 | 仍走 `claude-code-deepseek-*` Anthropic messages 路由，不应落到 `claw-deepseek-v4-flash` |

### 5. Good/Base/Bad Cases

- Good: Hermes 等 OpenAI 兼容 agent 使用 `model=claw-plan`，Base URL 指向 LiteLLM `/v1`，GLM 失败后自动 fallback 到 DeepSeek V4 Flash 最大思考模式。
- Good: 调试时直接调用 `claw-glmplan-5.1` 或 `claw-deepseek-v4-flash`，两者在 `/models` 中显式可见。
- Base: 现有 `GLM-5.1` / `GLM-*` 官方模型名仍按原路径转发到智谱 Coding Plan。
- Bad: 让 `claw-plan` 的 `litellm_params.model` 指向 `claw-glmplan-5.1` 这类对外别名，导致 Router 分组和 fallback 语义依赖二次解析。
- Bad: `claw-deepseek-v4-flash` 复用 `DEEPSEEK_ANTHROPIC_API_BASE` 或 `anthropic/deepseek-v4-flash`，把 OpenAI 兼容 agent 流量混入 Claude Code 专用链路。
- Bad: 为了复用现有兜底，把 `claw-plan` fallback 到 `claude-code-deepseek-v4-flash`，导致 OpenAI 兼容请求继承 Anthropic messages sanitizer 假设。

### 6. Tests Required

- Config parse: `litellm.local.yaml` 与 `newapi.yaml` 必须能被项目现有 YAML 解析方式读取。
- Config sync: 两份配置都必须包含 `claw-plan`、`claw-glmplan-5.1`、`claw-deepseek-v4-flash` 以及对应 fallback 规则。
- Env contract: `compose.yaml`、`.env.example`、`.env.production.example` 必须包含 `DEEPSEEK_OPENAI_API_BASE`。
- Parameter contract: `claw-deepseek-v4-flash` 必须配置 `reasoning_effort: "max"`。
- Runtime note: 真实 fallback 依赖上游额度、密钥和实时响应；本地配置验证不能证明线上额度恢复或供应商端协议行为。

---

## Scenario: Claude Code GLM 429 Fallback 到 DeepSeek

### 1. Scope / Trigger

- Trigger: 修改 `ai/gateway/litellm/*.yaml` 中 Claude Code GLM 入口、DeepSeek 兜底别名、`router_settings.fallbacks`、`additional_drop_params`、`litellm_settings.callbacks`、`callbacks/gateway_callback.py`、`callbacks/framework/**`、`callbacks/adapters/**` 或 `litellm_settings.modify_params`。
- Scope: `cc-glmplan-opus` / `cc-glmplan-haiku` 主路由优先使用智谱 GLM Coding Plan；GLM 返回 429 或 LiteLLM `RateLimitError` 后短重试，仍失败才 fallback 到 DeepSeek Anthropic 兼容端点；GLM 额度 429 返回 reset 时间后，callback adapter 在 reset 后延迟恢复前会预先避让 GLM。
- Design intent: 主路由尽量保留 Claude Code extended thinking；兜底路由优先保证请求不中断。

### 2. Signatures

- Client-facing model names:
  - `cc-glmplan-opus`
  - `cc-glmplan-haiku`
  - `claude-code-deepseek-v4-pro`
  - `claude-code-deepseek-v4-flash`
- Provider model mapping:
  - `cc-glmplan-*` -> `anthropic/GLM-5.1`
  - `claude-code-deepseek-v4-pro` -> `anthropic/deepseek-v4-pro[1m]`
  - `claude-code-deepseek-v4-flash` -> `anthropic/deepseek-v4-flash`
- Router fallback contract:
  - `cc-glmplan-opus` -> `claude-code-deepseek-v4-pro`
  - `cc-glmplan-haiku` -> `claude-code-deepseek-v4-flash`

### 3. Contracts

- Required environment keys:
  - `Z_AI_ANTHROPIC_API_BASE`: 智谱 Anthropic 兼容端点。
  - `Z_AI_API_KEY`: 智谱 Coding Plan 密钥。
  - `DEEPSEEK_ANTHROPIC_API_BASE`: DeepSeek Anthropic 兼容端点。
  - `DEEPSEEK_API_KEY`: DeepSeek 密钥。
  - `LITELLM_MASTER_KEY`: LiteLLM 对外鉴权密钥。
- Fallback-only parameter policy:
  - `claude-code-deepseek-*` 是 Claude Code Anthropic messages 专用兜底入口，必须保留当前请求的 top-level `thinking`、`reasoning_effort` 与 `output_config.effort`；不得再通过 `additional_drop_params` 丢弃 `thinking` / `reasoning_effort`。
  - Claude `/v1/messages` 原生路径必须启用 `callbacks.gateway_callback.proxy_handler_instance`，并由其中的 DeepSeek thinking sanitizer adapter 处理 DeepSeek 请求，因为该路径会把历史 `messages[].content[]` 直接传给上游，`additional_drop_params` 不能移除 `content[].thinking` / `redacted_thinking` 内容块。
  - DeepSeek 官方 Claude Code 直连配置推荐 `CLAUDE_CODE_EFFORT_LEVEL=max`；在 Anthropic 兼容接口里，DeepSeek 的 effort 语义对应 `output_config.effort`，不是 OpenAI 兼容接口里的 `reasoning_effort`。
  - 原生 Anthropic messages fallback 的核心问题是历史 assistant thinking 内容块有两类语义：带 `signature` 的 `thinking` 与带 `data` 的 `redacted_thinking` 是上游要求完整回传的不透明块；缺少签名/不透明数据的 thinking 块通常来自跨供应商或中间层转换，DeepSeek 无法校验。sanitizer 应保留可回传块，只清理不兼容块与 `thinking_blocks` 辅助字段。
  - 不得把 `thinking`、`reasoning_effort`、`output_config` 或 `output_config.effort` 加入 DeepSeek Claude Code 兜底别名的 `additional_drop_params`；DeepSeek Anthropic 兼容接口使用 top-level thinking 与 `output_config.effort` 承接 Claude Code effort。
  - 如果未来需要面向 Chat/Responses 的保守 DeepSeek 兼容入口，应新增独立 safe 路由，而不是让 `claude-code-deepseek-*` 牺牲 Claude Code thinking 能力。
  - 不得在 GLM 主路由上全局禁用 Claude Code thinking。
- LiteLLM settings:
  - `drop_params: true` 用于丢弃上游不识别的普通参数。
  - `modify_params: true` 用于允许 LiteLLM 修正 Anthropic tool/thinking 历史块兼容问题。
  - `callbacks` 必须包含统一入口 `callbacks.gateway_callback.proxy_handler_instance`；`compose.yaml` 必须挂载 `./callbacks:/app/callbacks:ro`，否则配置中的 Python 回调无法导入。
  - callback 顶层目录只放 LiteLLM import 入口：`gateway_callback.py`。框架基础设施放在 `callbacks/framework/**`，供应商能力放在 `callbacks/adapters/<provider>/**`，离线测试放在 `callbacks/tests/**`。
  - `GatewayCallbackHub` 是唯一主入口，负责把 LiteLLM 生命周期 hook 分发给启用的 adapter；adapter 默认 fail-open，异常日志不得包含 prompt、API key、完整 headers 或完整 request body。
  - `GlmCooldownAdapter` 必须只对 `cc-glmplan-opus` / `cc-glmplan-haiku` 的 GLM 额度或限流错误生效；识别到 reset 时间时按 `reset + LITELLM_GLM_RESET_BUFFER_SECONDS` 冷却，无法解析 reset 但确认是额度/限流错误时使用 `LITELLM_GLM_FALLBACK_COOLDOWN_SECONDS` 兜底。
  - GLM cooldown adapter 在冷却期间应于 Router 选部署前把 `cc-glmplan-opus` 改写为 `claude-code-deepseek-v4-pro`，把 `cc-glmplan-haiku` 改写为 `claude-code-deepseek-v4-flash`；不得影响 GLM 非 Claude Code 路由或其它供应商。
  - DeepSeek sanitizer 修改真实请求体时必须使用 `async_pre_call_deployment_hook`。该 hook 在 Router 选中 fallback 部署后、provider 构造 Anthropic messages 请求体前运行，可以基于 `litellm_metadata.deployment` / `deployment_model_name` / `api_base` 识别 DeepSeek 兜底部署。
  - Anthropic messages pass-through 会把 `messages` 作为位置参数继续传给 handler；sanitizer 不能只给 `kwargs["messages"]` 赋一个新列表，必须原地修改原 `messages` 列表引用，否则 provider request body 仍可能使用未清理的历史。
  - DeepSeek fallback 的 sanitizer 必须递归清理 content 结构，覆盖 `messages[*].content[*]`、嵌套 tool/result content、`thinking_blocks` 与 `redacted_thinking`；真实 Claude Code 历史不保证 thinking 只出现在第一层 content 列表。
  - sanitizer 只能删除不兼容 thinking：无非空 `signature` 的 `type: thinking`、无非空 `data` 的 `type: redacted_thinking`、以及 message-level `thinking_blocks` 辅助字段。带签名的 thinking 与带 data 的 redacted thinking 必须原样保留，否则 DeepSeek/Anthropic thinking mode 会报 `content[].thinking ... must be passed back`。
  - sanitizer 结构诊断日志只允许输出模型、hook 阶段、deployment metadata、清理数量、剩余不兼容 thinking 路径和已保留 thinking 路径；不得输出 prompt 正文、API key、完整 headers 或完整 request body。日志事件名固定为 `deepseek thinking sanitized`，`remaining_thinking_paths: []` 只表示请求结构已没有不兼容 thinking，`preserved_thinking_paths` 非空是正常现象。
  - sanitizer 的诊断扫描必须容忍非标准结构；例如 content block 的 `type` 可能被上游/客户端构造成非字符串值，日志扫描不得因为 `dict in set` 之类假设抛异常并中断 LiteLLM pre-call。
  - sanitizer 不得把顶层 `thinking` 降级为 `{"type": "disabled"}`；DeepSeek 会拒绝 disabled thinking 与 effort 参数共存，而保留 top-level thinking 并清掉历史 thinking 块可以让 DeepSeek 继续以 thinking 模式处理请求。
  - sanitizer 触发边界以“Router 已选中的目标部署是 DeepSeek Anthropic 兼容端点”为准，而不是强依赖 `fallback_depth`；`fallback_depth > 0` 只能作为日志诊断字段，用于确认请求是否真的由 `cc-glmplan-*` fallback 而来。这样既不影响 GLM 正常路径，也能保护用户直接调用 `claude-code-deepseek-*` 兼容入口时的同类请求。
  - `log_pre_api_call` 只能作为日志上下文与最终 `complete_input_dict` 的兜底清理点，不能作为唯一请求改写机制；Anthropic messages handler 会先构造请求体并可能执行 `sign_request`，再进入 logging pre-call，若实际发送体已经序列化，日志 hook 里的字典修改不会稳定改变上游收到的 JSON。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| GLM 正常可用 | `cc-glmplan-*` 直接走 GLM，保留 Claude Code thinking 语义 |
| GLM 返回 429 / `RateLimitError` | LiteLLM 先按 retry policy 短重试 |
| GLM 短重试耗尽 | Router fallback 到对应 `claude-code-deepseek-*` |
| GLM 429 错误体包含 reset 时间 | callback adapter 记录 `reset + 60 秒` 的冷却截止时间 |
| GLM 仍在 adapter 冷却期 | 请求进入 Router 前直接改写到对应 DeepSeek fallback，避免 5 小时额度窗口内重复撞限流 |
| GLM 429 不是额度/限流错误 | 不记录 5 小时兜底冷却，避免普通上游错误导致长时间避让 |
| DeepSeek 收到顶层 `thinking` / `reasoning_effort` | Claude Code DeepSeek 兜底路由应保留这些当前请求参数；sanitizer 只处理历史 content thinking 块 |
| DeepSeek 收到带签名/不透明数据的历史 `content[].thinking` / `redacted_thinking` | sanitizer 必须原样保留这些块；DeepSeek thinking mode 需要它们维持工具调用回合的推理连续性 |
| DeepSeek 收到无签名/不完整的历史 `content[].thinking` / `redacted_thinking` | sanitizer 必须在 deployment pre-call 阶段移除这些不兼容块，否则 DeepSeek 可能返回 thinking 历史校验错误 |
| DeepSeek 返回 `thinking options type cannot be disabled when reasoning_effort is set` | 优先检查 sanitizer 是否错误设置了 `top_level_thinking_after: disabled`；正确策略是保留 top-level thinking，而不是 disabled + effort 共存 |
| Sanitizer `log_pre_api_call` 自身抛 `TypeError: unhashable type: 'dict'` | 说明结构诊断函数假设了字段类型；修复方向是让诊断扫描容错，而不是放弃日志或输出完整请求体 |
| Sanitizer 日志显示 `remaining_thinking_paths: []` 但仍报 `content[].thinking ... must be passed back` | 优先检查 `preserved_thinking_blocks_after` 是否异常变少；这通常说明必须回传的 signed/redacted thinking 被误删 |
| DeepSeek 收到 `output_config.effort` 且 top-level thinking 保留 | 允许；这是 DeepSeek Anthropic 兼容接口承接 effort 的路径 |
| 历史消息缺少完整 `thinking_blocks` | `modify_params` 允许 LiteLLM 做兼容修正，避免 fallback 被 Anthropic 兼容端点拒绝 |
| Sanitizer 只实现 `log_pre_api_call` | 视为不满足请求改写合同；该 hook 可能只能改日志视图，不能保证修改已签名/已序列化的 Anthropic messages 请求体 |
| GLM 与 DeepSeek 都失败 | LiteLLM 将最终错误返回给 Claude Code，不伪装成功 |

### 5. Good/Base/Bad Cases

- Good: GLM 429 后切到 DeepSeek，原生 Anthropic `/v1/messages` fallback 保留当前 top-level `thinking`，同时只移除无签名/不完整的历史 thinking content 块。
- Good: GLM 额度 429 返回 `您的限额将在 ... 重置` 后，后续 `cc-glmplan-*` 请求在 reset + buffer 前由 callback adapter 预先切到对应 DeepSeek fallback。
- Good: callback 目录按 `framework/`、`adapters/<provider>/`、`tests/` 分层，顶层只保留 LiteLLM 配置直接 import 的薄入口。
- Good: sanitizer 原地修改 `messages` 列表并递归清理嵌套 content；日志显示 `top_level_thinking_before: enabled/adaptive`、`top_level_thinking_after: enabled/adaptive`、`remaining_thinking_paths: []`，同时 `preserved_thinking_blocks_after` 可大于 0。
- Good: DeepSeek 兜底别名不丢弃 `thinking`、`reasoning_effort` 或 `output_config.effort`；如果 Claude Code / LiteLLM 以 DeepSeek Anthropic 官方字段表达 effort，`CLAUDE_CODE_EFFORT_LEVEL=max` 仍有机会透传。
- Base: GLM 正常响应时不触发 fallback，不改变 Claude Code 对 GLM 主路由的 thinking 使用方式。
- Bad: 全局丢弃 `thinking`，导致 GLM 主路由也失去 Claude Code extended thinking 能力。
- Bad: sanitizer 为了绕过历史校验而设置 `thinking: disabled`，导致 DeepSeek 报 `thinking options type cannot be disabled when reasoning_effort is set`。
- Bad: sanitizer 删除所有 `content[].thinking`，导致 DeepSeek 在带工具调用历史的 thinking mode 中报 `content[].thinking in the thinking mode must be passed back`。
- Bad: sanitizer 诊断函数直接用 `value.get("type") in THINKING_BLOCK_TYPES`，真实请求里 `type` 是 dict 时会在 LiteLLM logging pre-call 阶段抛异常，反而遮蔽 fallback 的真实错误。
- Bad: 为了兼容 Chat/Responses，把 `claude-code-deepseek-*` 继续配置成丢弃 `thinking` / `reasoning_effort`，导致 Claude Code 兜底链路失去 DeepSeek thinking / effort 能力。
- Bad: 把所有 adapter 平铺在 `callbacks/` 顶层，导致 LiteLLM import 入口、框架抽象、供应商实现和测试混在同一目录。

### 6. Tests Required

- Config parse: YAML 必须能被项目现有解析方式读取。
- Config sync: 如果 `newapi.yaml` 与 `litellm.local.yaml` 应保持一致，修改后需要确认两者没有非预期差异。
- Route contract: 检查 `router_settings.fallbacks` 仍指向专用 DeepSeek 兜底别名。
- Parameter contract: 检查 `claude-code-deepseek-*` 不再配置 `additional_drop_params` 丢弃 `thinking` / `reasoning_effort`；如果出现 safe 兼容路由，其命名必须与 Claude Code 兜底路由区分。
- Callback contract: 检查 `callbacks.gateway_callback.proxy_handler_instance` 能在 LiteLLM 镜像内导入，并实现 `async_pre_call_hook`、`async_pre_call_deployment_hook`、`async_log_failure_event` 与 `log_pre_api_call` 的 adapter 分发。
- Hook-stage contract: 离线测试必须直接调用 `async_pre_call_deployment_hook`，输入包含 `litellm_metadata.deployment` / `deployment_model_name` / `api_base`、顶层 `thinking` / `reasoning_effort`、历史 `content[].thinking` / `redacted_thinking`，断言清理发生在 provider 请求体构造前。
- GLM cooldown contract: 离线测试必须覆盖 GLM 429 中文 reset 时间解析、`reset + 60 秒` 计算、解析失败但确认限流时的固定兜底冷却、非限流错误不记录长冷却、冷却期间 `cc-glmplan-*` 请求前改写到对应 DeepSeek fallback。
- Reference contract: 离线测试必须断言原始 `messages` 列表对象 ID 不变，且清理后 `kwargs["messages"] is messages`；这是 Anthropic messages pass-through 位置参数链路的关键行为。
- Recursive contract: 离线测试必须包含嵌套 content 中的 `redacted_thinking`、signed `thinking`、unsigned `thinking` 和 message-level `thinking_blocks`，并断言 unsigned/incomplete thinking 被清理、signed/redacted opaque thinking 被保留、`thinking_paths(...)` 在清理后为空。
- Diagnostic robustness contract: 离线测试必须覆盖 content block `type` 为非字符串的异常结构，断言 `thinking_paths(...)` 不抛异常且只报告真实 thinking block 路径。
- Current thinking contract: 离线测试必须覆盖 top-level `thinking`、`reasoning_effort` 与 `output_config.effort`，断言 sanitizer 清理历史 thinking 后仍保留这些当前请求参数。
- Runtime smoke contract: 真实验证可用 `/v1/messages?beta=true` 先直打 `claude-code-deepseek-v4-pro`，再打 `cc-glmplan-opus` 触发 429 fallback；成功样本应返回 HTTP 200，容器日志应有两个阶段的 `deepseek thinking sanitized`、`remaining_thinking_paths: []`，并允许 `preserved_thinking_blocks_after > 0`。
- Runtime callback contract: 重启 LiteLLM 后调用 `/active/callbacks`，确认运行态 `litellm.callbacks` 包含 `callbacks.gateway_callback.GatewayCallbackHub` 或等价统一入口；不要用 `docker exec python` 新进程里的 `litellm.callbacks` 判断服务进程状态。
- Runtime note: 真实 429 fallback 依赖上游额度、密钥和实时响应；本地配置验证不能证明线上额度恢复或供应商端协议行为。

### 7. Wrong vs Correct

#### Wrong

```yaml
litellm_settings:
  drop_params: true

model_list:
  - model_name: "cc-glmplan-opus"
    litellm_params:
      model: "anthropic/GLM-5.1"
  - model_name: "claude-code-deepseek-v4-pro"
    litellm_params:
      model: "anthropic/deepseek-v4-pro[1m]"
```

问题：只配置 DeepSeek 路由而不挂载 sanitizer，会让跨供应商 fallback 的历史 thinking 内容块直接进入 DeepSeek；历史消息缺少完整签名或不透明数据时会触发 `invalid_request_error`。

#### Correct

```yaml
model_list:
  - model_name: "claude-code-deepseek-v4-pro"
    litellm_params:
      model: "anthropic/deepseek-v4-pro[1m]"

litellm_settings:
  drop_params: true
  modify_params: true
  callbacks:
    - callbacks.gateway_callback.proxy_handler_instance
```

理由：DeepSeek 兜底别名是 Claude Code 降级链路专用入口，应保留当前请求的 thinking / effort 能力；gateway callback hub 分发给 DeepSeek sanitizer adapter 与 GLM cooldown adapter，sanitizer 只处理 Anthropic `/v1/messages` 历史 content thinking 块，两者不能互相替代。

#### DeepSeek effort vs thinking

```yaml
model_list:
  - model_name: "claude-code-deepseek-v4-pro"
    litellm_params:
      model: "anthropic/deepseek-v4-pro[1m]"
      # 不要在 Claude Code 兜底路由上丢弃 thinking / reasoning_effort / output_config.effort；
      # DeepSeek Anthropic 兼容接口用它们承接 Claude Code thinking / effort。
```

结论：`CLAUDE_CODE_EFFORT_LEVEL=max` 是 DeepSeek 官方 Claude Code 直连推荐配置；在 DeepSeek Anthropic 兼容接口里，effort 对应 `output_config.effort`。原生 Anthropic messages fallback 不应把当前请求降级为 `thinking: disabled`，否则会与 effort 冲突；正确做法是保留当前 thinking/effort，只清理历史 assistant thinking 块。

#### Anthropic messages sanitizer

```yaml
litellm_settings:
  callbacks:
    - callbacks.gateway_callback.proxy_handler_instance
```

说明：Claude Code 使用 `/v1/messages?beta=true` 时，LiteLLM 走 Anthropic 原生 messages pass-through。该路径的 `messages` 与 `thinking` 不走普通 OpenAI 参数映射，`additional_drop_params` 不能删除历史 `messages[*].content[*]` 中的 thinking 内容块。DeepSeek 返回 `content[].thinking in the thinking mode must be passed back` 时，应先确认 sanitizer 是否误删了带 `signature` 的 thinking 或带 `data` 的 redacted thinking，而不是只改 `additional_drop_params`。

Sanitizer 必须原地修改 `messages` 列表：

```python
messages[:] = sanitized_messages
```

说明：`async_pre_call_deployment_hook` 返回的 `kwargs` 会被 LiteLLM 回灌，但 Anthropic messages handler 后续仍可能继续使用函数位置参数里的原 `messages` 引用。只做 `kwargs["messages"] = sanitized_messages` 会让 hook 看起来已清理，实际 provider request body 仍带旧 content。递归清理后如果真实请求仍失败，应先查 `deepseek thinking sanitized` 日志：`remaining_thinking_paths` 非空说明清理范围不够；为空则说明错误已经转移到 DeepSeek/Anthropic 的其它协议校验。

#### Hook stage: request mutation vs logging

```python
class DeepSeekThinkingSanitizer(CustomLogger):
    async def async_pre_call_deployment_hook(self, kwargs, call_type):
        # 正确：Router 已选中 fallback 部署，provider 尚未构造/签名实际 Anthropic 请求体。
        ...

    def log_pre_api_call(self, model, messages, kwargs):
        # 仅可作为兜底同步日志上下文；不要把它当作唯一请求改写入口。
        ...
```

说明：LiteLLM 的 hook 名称容易让人误判阶段。`async_pre_call_deployment_hook` 是“部署已选、请求尚未送入 provider”的改写点；`log_pre_api_call` 是 provider 内部 logging pre-call，Anthropic messages 路径进入这里时请求体已经完成 transform，部分 provider 还可能已经生成 `signed_json_body`。任何跨供应商 fallback 的请求兼容清洗，都应优先放在 deployment pre-call，并用实际 fallback deployment metadata 判断目标上游。

#### Deferred option: two-stage DeepSeek fallback

```yaml
router_settings:
  fallbacks:
    - cc-glmplan-opus:
        - claude-code-deepseek-v4-pro
        - claude-code-deepseek-v4-pro-safe
```

说明：可以先尝试完整 DeepSeek 路由，再 fallback 到只清理历史 thinking 块的 safe 路由，以尽量保留 DeepSeek 官方 thinking 能力。但 LiteLLM YAML 不能按 DeepSeek 返回的精确错误文本改写同一请求后重放；两级路由会增加配置复杂度和一次失败重试延迟。当前策略选择让 `claude-code-deepseek-*` 保留当前 thinking / effort，并由 sanitizer 在单一路由内清理历史 thinking 块。
