# LiteLLM Gateway Spec

> 本规范记录 `ai/gateway/litellm` 的路由与跨供应商兼容约定。修改 LiteLLM 配置、Claude Code 网关入口或模型 fallback 时必须先阅读。

---

## Scenario: Claude Code GLM 429 Fallback 到 DeepSeek

### 1. Scope / Trigger

- Trigger: 修改 `ai/gateway/litellm/*.yaml` 中 Claude Code GLM 入口、DeepSeek 兜底别名、`router_settings.fallbacks`、`additional_drop_params`、`litellm_settings.callbacks`、`callbacks/deepseek_thinking_sanitizer*.py` 或 `litellm_settings.modify_params`。
- Scope: `cc-glmplan-opus` / `cc-glmplan-haiku` 主路由优先使用智谱 GLM Coding Plan；GLM 返回 429 或 LiteLLM `RateLimitError` 后短重试，仍失败才 fallback 到 DeepSeek Anthropic 兼容端点。
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
  - DeepSeek 兜底别名必须显式丢弃 `thinking` 与 `reasoning_effort`。
  - Claude `/v1/messages` 原生路径必须启用 `callbacks.deepseek_thinking_sanitizer.proxy_handler_instance`，因为该路径会把历史 `messages[].content[]` 直接传给上游，`additional_drop_params` 不能移除 `content[].thinking` / `redacted_thinking` 内容块。
  - DeepSeek 官方 Claude Code 直连配置推荐 `CLAUDE_CODE_EFFORT_LEVEL=max`；在 Anthropic 兼容接口里，DeepSeek 的 effort 语义对应 `output_config.effort`，不是 OpenAI 兼容接口里的 `reasoning_effort`。
  - 不得把 `output_config` 加入 DeepSeek 兜底别名的 `additional_drop_params`；当前只丢弃 `thinking` 与 `reasoning_effort`，避免误伤 DeepSeek 官方 Anthropic effort 参数。
  - 丢弃 `thinking` 会让 DeepSeek 兜底不再显式请求 extended thinking；这是用 fallback 质量上限换取 GLM 429 后链路不中断。
  - 丢弃范围只绑定到 DeepSeek 兜底别名；不得在 GLM 主路由上全局禁用 Claude Code thinking。
  - 如果 `claude-code-deepseek-*` 被直接调用，也会应用同一丢弃策略；因此该别名应被视为 fallback/兼容专用入口。
- LiteLLM settings:
  - `drop_params: true` 用于丢弃上游不识别的普通参数。
  - `modify_params: true` 用于允许 LiteLLM 修正 Anthropic tool/thinking 历史块兼容问题。
  - `callbacks` 必须包含 DeepSeek thinking sanitizer；`compose.yaml` 必须挂载 `./callbacks:/app/callbacks:ro`，否则配置中的 Python 回调无法导入。
  - DeepSeek sanitizer 修改真实请求体时必须使用 `async_pre_call_deployment_hook`。该 hook 在 Router 选中 fallback 部署后、provider 构造 Anthropic messages 请求体前运行，可以基于 `litellm_metadata.deployment` / `deployment_model_name` / `api_base` 识别 DeepSeek 兜底部署。
  - Anthropic messages pass-through 会把 `messages` 作为位置参数继续传给 handler；sanitizer 不能只给 `kwargs["messages"]` 赋一个新列表，必须原地修改原 `messages` 列表引用，否则 provider request body 仍可能使用未清理的历史。
  - DeepSeek fallback 的 sanitizer 必须递归清理 content 结构，覆盖 `messages[*].content[*]`、嵌套 tool/result content、`thinking_blocks` 与 `redacted_thinking`；真实 Claude Code 历史不保证 thinking 只出现在第一层 content 列表。
  - sanitizer 结构诊断日志只允许输出模型、hook 阶段、deployment metadata、清理数量和剩余 thinking 路径；不得输出 prompt 正文、API key、完整 headers 或完整 request body。日志事件名固定为 `deepseek thinking sanitized`，`remaining_thinking_paths: []` 才表示请求结构已清理干净。
  - `log_pre_api_call` 只能作为日志上下文与最终 `complete_input_dict` 的兜底清理点，不能作为唯一请求改写机制；Anthropic messages handler 会先构造请求体并可能执行 `sign_request`，再进入 logging pre-call，若实际发送体已经序列化，日志 hook 里的字典修改不会稳定改变上游收到的 JSON。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| GLM 正常可用 | `cc-glmplan-*` 直接走 GLM，保留 Claude Code thinking 语义 |
| GLM 返回 429 / `RateLimitError` | LiteLLM 先按 retry policy 短重试 |
| GLM 短重试耗尽 | Router fallback 到对应 `claude-code-deepseek-*` |
| DeepSeek 收到顶层 `thinking` / `reasoning_effort` | 兜底别名的 `additional_drop_params` 覆盖普通 Chat/Responses 路径；原生 Anthropic messages 路径由 sanitizer 在 HTTP pre-call 阶段移除 |
| DeepSeek 收到历史 `content[].thinking` / `redacted_thinking` | sanitizer 必须在 deployment pre-call 阶段移除这些历史块，否则 DeepSeek 会返回 `content[].thinking in the thinking mode must be passed back` |
| Sanitizer 日志显示 `remaining_thinking_paths: []` 但仍失败 | 优先看 DeepSeek 返回的新错误文本；这通常说明 thinking 已清完，剩余问题是 Anthropic 协议形态错误、工具块角色错误或上游其他校验 |
| DeepSeek 收到 `output_config.effort` | 不应通过 `additional_drop_params` 丢弃；这是 DeepSeek Anthropic 兼容接口承接 `CLAUDE_CODE_EFFORT_LEVEL=max` 的官方字段 |
| 历史消息缺少完整 `thinking_blocks` | `modify_params` 允许 LiteLLM 做兼容修正，避免 fallback 被 Anthropic 兼容端点拒绝 |
| Sanitizer 只实现 `log_pre_api_call` | 视为不满足请求改写合同；该 hook 可能只能改日志视图，不能保证修改已签名/已序列化的 Anthropic messages 请求体 |
| GLM 与 DeepSeek 都失败 | LiteLLM 将最终错误返回给 Claude Code，不伪装成功 |

### 5. Good/Base/Bad Cases

- Good: GLM 429 后切到 DeepSeek，DeepSeek 不接收 `thinking` / `reasoning_effort`，请求以普通非-thinking 模式继续完成。
- Good: 原生 Anthropic `/v1/messages` fallback 到 DeepSeek 前，sanitizer 移除顶层 `thinking` 和历史 `thinking` / `redacted_thinking` content 块。
- Good: sanitizer 原地修改 `messages` 列表并递归清理嵌套 content；日志显示 `top_level_thinking_before: enabled`、`top_level_thinking_after: disabled`、`remaining_thinking_paths: []`。
- Good: DeepSeek 兜底别名不丢弃 `output_config.effort`；如果 Claude Code / LiteLLM 以 DeepSeek Anthropic 官方字段表达 effort，`CLAUDE_CODE_EFFORT_LEVEL=max` 仍有机会透传。
- Base: GLM 正常响应时不触发 fallback，不改变 Claude Code 对 GLM 主路由的 thinking 使用方式。
- Bad: 全局丢弃 `thinking`，导致 GLM 主路由也失去 Claude Code extended thinking 能力。
- Bad: DeepSeek 兜底别名保留 `thinking`，fallback 后报 `content[].thinking` / `thinking_blocks` 相关 `invalid_request_error`。
- Bad: 看到 DeepSeek 官方推荐 `CLAUDE_CODE_EFFORT_LEVEL=max` 后，把 fallback 别名改成保留 `thinking`；直连 DeepSeek 与跨供应商 fallback 的历史消息完整性不同，不能混为一谈。

### 6. Tests Required

- Config parse: YAML 必须能被项目现有解析方式读取。
- Config sync: 如果 `newapi.yaml` 与 `litellm.local.yaml` 应保持一致，修改后需要确认两者没有非预期差异。
- Route contract: 检查 `router_settings.fallbacks` 仍指向专用 DeepSeek 兜底别名。
- Parameter contract: 检查 `additional_drop_params` 只出现在 DeepSeek 兜底别名或其它明确的兼容专用路由上。
- Callback contract: 检查 `callbacks.deepseek_thinking_sanitizer.proxy_handler_instance` 能在 LiteLLM 镜像内导入，并实现 `async_pre_call_deployment_hook`，能在 `CallTypes.anthropic_messages` 且 deployment metadata 指向 DeepSeek 时原地清理请求参数。
- Hook-stage contract: 离线测试必须直接调用 `async_pre_call_deployment_hook`，输入包含 `litellm_metadata.deployment` / `deployment_model_name` / `api_base`、顶层 `thinking` / `reasoning_effort`、历史 `content[].thinking` / `redacted_thinking`，断言清理发生在 provider 请求体构造前。
- Reference contract: 离线测试必须断言原始 `messages` 列表对象 ID 不变，且清理后 `kwargs["messages"] is messages`；这是 Anthropic messages pass-through 位置参数链路的关键行为。
- Recursive contract: 离线测试必须包含嵌套 content 中的 `redacted_thinking` 和 message-level `thinking_blocks`，并断言 `thinking_paths(...)` 在清理后为空。
- Runtime smoke contract: 真实验证可用 `/v1/messages?beta=true` 先直打 `claude-code-deepseek-v4-pro`，再打 `cc-glmplan-opus` 触发 429 fallback；成功样本应返回 HTTP 200，容器日志应有两个阶段的 `deepseek thinking sanitized` 且 `remaining_thinking_paths: []`。
- Runtime callback contract: 重启 LiteLLM 后调用 `/active/callbacks`，确认运行态 `litellm.callbacks` 包含 `callbacks.deepseek_thinking_sanitizer.DeepSeekThinkingSanitizer`；不要用 `docker exec python` 新进程里的 `litellm.callbacks` 判断服务进程状态。
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

问题：DeepSeek 兜底仍可能收到 Claude Code extended thinking 参数；跨供应商 fallback 时，历史消息缺少完整 `thinking_blocks` 会触发 `invalid_request_error`。

#### Correct

```yaml
model_list:
  - model_name: "claude-code-deepseek-v4-pro"
    litellm_params:
      model: "anthropic/deepseek-v4-pro[1m]"
      additional_drop_params:
        - reasoning_effort
        - thinking

litellm_settings:
  drop_params: true
  modify_params: true
  callbacks:
    - callbacks.deepseek_thinking_sanitizer.proxy_handler_instance
```

理由：DeepSeek 兜底别名是降级链路专用入口，优先保证 GLM 429 后可用；主 GLM 路由仍保留 Claude Code extended thinking。`additional_drop_params` 处理普通参数，sanitizer 处理 Anthropic `/v1/messages` 历史内容块，两者不能互相替代。

#### DeepSeek effort vs thinking

```yaml
model_list:
  - model_name: "claude-code-deepseek-v4-pro"
    litellm_params:
      model: "anthropic/deepseek-v4-pro[1m]"
      additional_drop_params:
        - reasoning_effort
        - thinking
        # 不要加入 output_config；DeepSeek Anthropic 兼容接口用它承接 effort。
```

结论：`CLAUDE_CODE_EFFORT_LEVEL=max` 是 DeepSeek 官方 Claude Code 直连推荐配置；在 DeepSeek Anthropic 兼容接口里，effort 对应 `output_config.effort`。兜底配置丢弃 `reasoning_effort` 主要影响 OpenAI 风格参数，丢弃 `thinking` 则会关闭显式 extended thinking。该取舍只应用于跨供应商 fallback，因为 GLM 生成的历史 `thinking` 块不一定满足 DeepSeek/Anthropic 兼容端点对完整 thinking 历史的校验。

#### Anthropic messages sanitizer

```yaml
litellm_settings:
  callbacks:
    - callbacks.deepseek_thinking_sanitizer.proxy_handler_instance
```

说明：Claude Code 使用 `/v1/messages?beta=true` 时，LiteLLM 走 Anthropic 原生 messages pass-through。该路径的 `messages` 与 `thinking` 不走普通 OpenAI 参数映射，`additional_drop_params` 不能删除历史 `messages[*].content[*]` 中的 thinking 内容块。DeepSeek 返回 `content[].thinking in the thinking mode must be passed back` 时，应先确认 sanitizer 已挂载并加载，而不是只改 `additional_drop_params`。

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

说明：可以先尝试完整 DeepSeek 路由，再 fallback 到丢弃 `thinking` / `reasoning_effort` 的 safe 路由，以尽量保留 DeepSeek 官方 thinking 能力。但 LiteLLM YAML 不能按 DeepSeek 返回的精确错误文本改写同一请求后重放；两级路由会增加配置复杂度和一次失败重试延迟。当前策略选择直接让 DeepSeek 兜底路由进入 safe 模式，优先保证 GLM 429 后 Claude Code 不被中断。
