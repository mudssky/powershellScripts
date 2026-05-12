# brainstorm: DeepSeek 兜底 thinking 参数策略

## Goal

厘清并收敛 `claude-code-deepseek-*` 兜底别名是否还需要在 `additional_drop_params` 中丢弃 `thinking` / `reasoning_effort`。目标是让 Claude Code 的 Anthropic `/v1/messages` fallback 保留 DeepSeek thinking 能力，同时避免 Chat/Responses 或 OpenAI 兼容路径把不兼容参数传给 DeepSeek。

## What I already know

* 用户质疑 `ai/gateway/litellm/litellm.local.yaml` 中 `claude-code-deepseek-v4-pro` 仍配置 `additional_drop_params: [reasoning_effort, thinking]`。
* 当前 sanitizer 已不再禁用 top-level `thinking`，并且只清理无签名/不完整的历史 thinking block；带 `signature` 的 `thinking` 与带 `data` 的 `redacted_thinking` 会保留。
* 运行态源码显示原生 Anthropic messages 路径只对 `additional_drop_params` 中的 dotted nested path 做删除；普通字段名 `thinking` / `reasoning_effort` 主要影响 Chat/Responses / OpenAI 兼容参数转换路径。
* DeepSeek Anthropic 兼容接口可接受 top-level `thinking: {"type": "adaptive"}` 与 `output_config.effort`，真实 smoke 已验证 `/v1/messages` fallback 返回 200。
* 用户已选择 Approach B：移除 `claude-code-deepseek-*` 的 `additional_drop_params`，把该别名定位为 Claude Code Anthropic messages 专用兜底入口。

## Assumptions (temporary)

* Claude Code 主路径是原生 Anthropic `/v1/messages?beta=true`，不是 OpenAI chat/completions。
* `claude-code-deepseek-*` 不承担 Chat/Responses 保守兼容职责；如果未来需要，应新增独立 safe 路由。

## Open Questions

* 无。

## Requirements (evolving)

* 明确 `additional_drop_params` 在 Anthropic messages 与 Chat/Responses 路径中的真实影响范围。
* 保持 GLM 429 fallback 到 DeepSeek 的 `/v1/messages` 链路可用。
* 避免再次引入 `thinking: disabled` 与 effort 冲突。
* 文档必须区分 “top-level current thinking 参数” 与 “历史 content thinking block”。
* `claude-code-deepseek-*` 不得通过 `additional_drop_params` 丢弃 `thinking` / `reasoning_effort`。

## Acceptance Criteria (evolving)

* [x] 选定并记录 `claude-code-deepseek-*` 是否保留 `additional_drop_params` 的策略。
* [x] 如果修改 YAML，`newapi.yaml` 与 `litellm.local.yaml` 保持预期一致。
* [x] `/v1/messages?beta=true` fallback 仍返回 200。
* [x] sanitizer 日志中 top-level `thinking` 不被降级，signed thinking 不被误删。
* [x] 文档与 Trellis spec 同步记录最终策略。

## Definition of Done (team quality bar)

* Tests added/updated (unit/integration where appropriate)
* Lint / typecheck / CI green
* Docs/notes updated if behavior changes
* Rollout/rollback considered if risky

## Out of Scope (explicit)

* 不在本任务中重写 LiteLLM Router fallback 机制。
* 不新增外部代理或替换 DeepSeek Anthropic 上游。
* 不处理 `.codex/config.toml` 与 `.shrimp-data/` 这些已有未提交工作区改动。

## Research Notes

### Code inspection

* `ai/gateway/litellm/litellm.local.yaml` 与 `ai/gateway/litellm/newapi.yaml` 的 DeepSeek 兜底别名仍配置 `additional_drop_params: [reasoning_effort, thinking]`。
* LiteLLM 容器内 `llm_http_handler.py` 的 Anthropic messages path 只从 `additional_drop_params` 中取 dotted nested path 并对 `anthropic_messages_optional_request_params` 做删除，普通字段名不会删除原生 messages 的 top-level `thinking`。
* LiteLLM `utils.py` 中 `_should_drop_param` 会让普通字段名 drop 作用于 OpenAI 兼容参数映射路径。

### Feasible approaches

**Approach A: 保守保留 drop（当前状态）**

* How it works: 保留 `additional_drop_params: [reasoning_effort, thinking]`，原生 `/v1/messages` 依靠 sanitizer 保留 top-level thinking；Chat/Responses 继续丢弃这两个参数。
* Pros: 对非 Claude Code 路径更保守，减少未知兼容风险。
* Cons: 配置语义容易误导，名字叫 Claude Code 但 Responses 路径会失去 thinking。

**Approach B: 移除 drop（推荐，如果该别名只给 Claude Code 用）**

* How it works: 从 `claude-code-deepseek-*` 别名移除 `additional_drop_params`，让 DeepSeek Anthropic 兼容接口接收当前 thinking/effort；历史 content block 仍由 sanitizer 清理。
* Pros: 语义最一致，DeepSeek thinking 能力不被配置层静默拿掉。
* Cons: 如果有人直接用该别名走 Chat/Responses，可能重新暴露 provider 参数兼容问题。

**Approach C: 拆路由**

* How it works: `claude-code-deepseek-*` 移除 drop，新增 `deepseek-compat-safe-*` 之类路由给 Chat/Responses 保守 drop。
* Pros: 能力与兼容边界最清晰。
* Cons: 配置更复杂，fallback 规则和文档都要增加维护成本。

## Technical Notes

* 相关文件：
  * `ai/gateway/litellm/litellm.local.yaml`
  * `ai/gateway/litellm/newapi.yaml`
  * `ai/gateway/litellm/callbacks/deepseek_thinking_sanitizer_core.py`
  * `.trellis/spec/infra/litellm-gateway.md`
  * `ai/gateway/litellm/litellm.md`
* Context7 查询 LiteLLM 文档未直接返回 `additional_drop_params` 专门章节；以运行容器源码为准。

## Decision (ADR-lite)

**Context**: `claude-code-deepseek-*` 是 GLM 429 后的 Claude Code Anthropic messages 兜底入口。上轮保留 `additional_drop_params: [thinking, reasoning_effort]` 是为了 Chat/Responses 路径保守兼容，但会让配置语义变成“Claude Code 兜底仍静默丢弃 thinking/effort”。

**Decision**: 采用 Approach B，移除 `claude-code-deepseek-*` 的 `additional_drop_params`。Claude Code 兜底路由保留当前 top-level `thinking`、`reasoning_effort` 与 `output_config.effort`；历史 content thinking 兼容仍由 sanitizer 处理。

**Consequences**: Claude Code fallback 保留 DeepSeek thinking / effort 能力；如果未来要支持 Chat/Responses 的保守 DeepSeek 兼容，应新增独立 safe 路由，而不是复用 `claude-code-deepseek-*`。
