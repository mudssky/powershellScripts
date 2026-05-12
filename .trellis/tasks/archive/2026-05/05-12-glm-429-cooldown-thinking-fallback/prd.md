# brainstorm: 优化 GLM 429 冷却与 fallback thinking 处理

## Goal

优化 Claude Code 通过 LiteLLM 使用 GLM Coding Plan 时的 429 处理：GLM 的额度窗口是 5 小时，而当前固定 1 小时 `cooldown_time` 会导致窗口内反复探测；同时把现有单用途 callback 演进为可组合的 LiteLLM callback adapter 框架，让 DeepSeek thinking sanitizer、GLM cooldown 等逻辑可以独立配置、独立测试、独立扩展。

## What I already know

* 用户提供的 GLM 429 示例会在错误体中返回中文重置时间：`已达到 5 小时的使用上限。您的限额将在 2026-05-08 05:32:56 重置。`
* 用户期望按错误体中的恢复时间再往后延 1 分钟恢复，避免中途多次多余请求。
* 当前 `ai/gateway/litellm/litellm.local.yaml` 中 `cc-glmplan-opus` / `cc-glmplan-haiku` 都配置 `cooldown_time: 3600`。
* `ai/gateway/litellm/newapi.yaml` 中对应配置同样是 `cooldown_time: 3600`，若改配置应同步。
* DeepSeek sanitizer 已迁移为 `callbacks.gateway_callback.proxy_handler_instance` 下的 adapter，旧单用途 callback 入口已删除。
* sanitizer 不是只在 fallback 时调用；LiteLLM 会按 callback 生命周期调用 hook，当前代码再用 call_type 与 DeepSeek deployment/api_base 过滤实际清理范围。
* GLM 正常路径不会被 sanitizer 清理；GLM fallback 到 DeepSeek 或直接调用 `claude-code-deepseek-*` 时会被清理。
* 当前 fallback thinking 报错更像是 DeepSeek 收到必须回传的 signed/redacted thinking 丢失或请求体未被正确清理导致；现有 spec 已要求保留带 `signature` / `data` 的 thinking 块。
* 用户希望基于 callback 全生命周期特性开发一个可兼容多种配置的框架，GLM cooldown 适配逻辑应能单独抽出。

## Assumptions (temporary)

* GLM 429 reset 时间使用 Asia/Shanghai 语义，错误体没有显式时区。
* “恢复时间 + 1 分钟”只针对智谱 GLM Coding Plan 5 小时额度 429，不应影响其它供应商或普通 429。
* 当前 LiteLLM YAML 没有直接支持“解析上游错误 body 后动态设置 deployment cooldown 到指定时间”的配置项。

## Open Questions

* 无。

## Requirements (evolving)

* 减少 GLM 5 小时额度窗口内的重复请求探测。
* 保持 `cc-glmplan-opus` fallback 到 `claude-code-deepseek-v4-pro`，`cc-glmplan-haiku` fallback 到 `claude-code-deepseek-v4-flash`。
* 保持 DeepSeek sanitizer 当前“按 DeepSeek Anthropic deployment 触发”的边界，不改成只看 fallback。
* 文档说明 callback 的生命周期含义：不是 fallback-only，fallback 只是其中一个会命中 DeepSeek 清理条件的场景。
* 新增 callback adapter 框架：LiteLLM 仍只挂载一个 `CustomLogger` 入口，该入口把各生命周期 hook 分发给多个 adapter。
* DeepSeek thinking sanitizer 作为一个 adapter 接入框架，保持现有行为不回退。
* GLM cooldown 作为独立 adapter 接入框架，负责识别 GLM 429 reset 时间并提供恢复时间策略。
* adapter 必须可以按配置启用/禁用，并能表达适用范围，例如 model group、deployment、provider、api_base 或错误码。
* 如果修改配置，`litellm.local.yaml` 与 `newapi.yaml` 需要保持预期一致。

## Acceptance Criteria (evolving)

* [x] GLM Claude Code 入口不再使用 1 小时冷却导致 5 小时窗口内反复探测。
* [x] 429 示例中的 reset 时间策略被记录或实现为“reset + 60 秒”。
* [x] LiteLLM 配置只需挂载统一 callback hub，具体行为由 adapter 注册/配置决定。
* [x] DeepSeek thinking sanitizer adapter 与 GLM cooldown adapter 可以单独测试。
* [x] DeepSeek fallback 的 thinking sanitizer 行为不回退：当前 top-level thinking/effort 保留，历史不兼容 thinking 清理，signed/redacted opaque thinking 保留。
* [x] 文档解释 callback 不是只在 fallback 时调用，并说明当前代码的过滤条件。
* [x] YAML 可被解析，相关 sanitizer 回归测试通过。

## Definition of Done

* Tests added/updated where behavior changes.
* `pnpm qa` 通过，或记录无法运行的原因。
* 若改动涉及 pwsh 相关内容，按项目规则额外执行对应 pwsh 测试。
* Docs/spec updated if behavior changes.
* Rollout/rollback considered if risky.

## Research References

* [`research/litellm-callback-router.md`](research/litellm-callback-router.md) — LiteLLM callback 生命周期与 Router 固定冷却能力调研。

## Research Notes

### Feasible approaches

**Approach A: 固定 5 小时冷却**

* How it works: 把两个 GLM Claude Code 入口的 `cooldown_time` 从 3600 改成 18000，并同步 `litellm.md` 与 Trellis spec。
* Pros: 改动小，能直接覆盖 5 小时窗口，减少中途多余请求。
* Cons: 不能利用错误体里的精确 reset 时间；如果 reset 时间与固定窗口不一致，仍可能早探测或晚恢复。

**Approach B: 动态解析 GLM reset 时间**

* How it works: 捕获 GLM 429 错误体，解析 reset 时间，按 reset + 60 秒让后续请求避让 GLM，期间直接使用 DeepSeek fallback。
* Pros: 最贴合真实上游返回，恢复更精准。
* Cons: LiteLLM 文档未暴露直接 YAML 配置，可能需要研究/使用内部 Router cooldown API 或本地缓存拦截，复杂度更高。

**Approach C: Callback hub + 独立 adapters（推荐）**

* How it works: 新增统一 callback hub 实现 LiteLLM `CustomLogger`，把生命周期 hook 分发给多个 adapter；现有 DeepSeek sanitizer 迁移为 request-mutation adapter，GLM cooldown 新增为 error/cooldown adapter。
* Pros: 结构清晰，后续可继续加入 provider-specific 兼容逻辑；GLM cooldown 不污染 DeepSeek sanitizer；每个 adapter 可以独立测试和配置。
* Cons: 初次改动比单纯改 YAML 大，需要设计 adapter 协议、配置读取、错误隔离与日志规范。

### Callback framework shape

**Recommended shape: hub + adapter registry**

* LiteLLM YAML 中挂载一个统一入口，例如 `callbacks.gateway_callback.proxy_handler_instance`。
* `GatewayCallbackHub(CustomLogger)` 实现 LiteLLM 常用 hook，并按顺序调用启用的 adapter。
* adapter 可以只实现自己关心的 hook；未实现的 hook 自动跳过。
* 单个 adapter 异常不能拖垮其它 adapter；框架记录安全日志，并按 adapter 标记决定是否 fail-open。
* 默认 adapter 列表由本地 Python 注册，配置负责启用/禁用和传入范围参数，避免在 YAML 中写 Python import 细节。

### Adapter lifecycle model

* `GatewayCallbackHub` 实现 LiteLLM 的生命周期 hook，并把同一个 hook 分发给所有启用且实现了该 hook 的 adapter。
* 所有 adapter 共享一个轻量 `GatewayCallbackAdapter` 协议/抽象基类，定义 `name`、`enabled`、异常策略与可选生命周期 hook。
* `SanitizerAdapter` 属于请求改写类 adapter，主要运行在 `async_pre_call_deployment_hook`，必要时在 `log_pre_api_call` 做诊断/兜底。
* `CooldownAdapter` 属于限流状态类 adapter，通常至少需要两个阶段：失败后 hook 解析 GLM 429 reset 时间并记录 `cooldown_until`；请求前 hook 根据 `cooldown_until` 决定是否避让 GLM 或提示 Router 不要选中该部署。
* `SanitizerAdapter` 和 `CooldownAdapter` 应作为分类抽象或 mixin 存在，沉淀该类别必须实现/推荐实现的 hook、配置模型与测试契约；具体实现例如 `DeepSeekThinkingSanitizerAdapter`、`GlmCooldownAdapter`。
* adapter 是可组合的：同一个生命周期阶段可以串行调用多个 adapter，不同职责的 adapter 不互相替代。
* adapter 是可替换的：例如未来可以把 `GlmCooldownAdapter` 替换成更通用的 `ProviderCooldownAdapter`，也可以把 DeepSeek sanitizer 替换成其它实现；替换范围限于同一职责/协议，不是用 cooldown 取代 sanitizer。

## Expansion Sweep

### Future evolution

* 后续可把 GLM 429 reset 时间缓存成 per-model-group 的恢复时间，让多个进程或容器共享状态。
* 如果其它供应商也返回可解析 reset 时间，可抽象为 provider-specific cooldown parser。
* callback adapter 框架可继续承接供应商参数修正、响应 header 注入、错误转换与观测日志。

### Related scenarios

* `cc-glmplan-opus` 与 `cc-glmplan-haiku` 应保持一致，否则 subagent/haiku 流量仍会撞额度。
* `litellm.local.yaml` 与 `newapi.yaml` 的模型配置要同步，避免本地与模板行为漂移。

### Failure & edge cases

* 429 body 可能不是 JSON，或中文 reset 时间格式变化；解析失败时应回退到固定 5 小时冷却。
* reset 时间可能已经过去；恢复时间应至少有一个很短的保护窗口，避免立即重试风暴。
* callback 诊断日志不能输出 prompt、API key、完整 headers 或完整 request body。
* 单个 adapter 出错时应默认 fail-open，除非该 adapter 明确声明该错误必须阻断请求。

## Technical Approach

推荐采用 `GatewayCallbackHub + adapters`：

* `DeepSeekThinkingSanitizerAdapter` 复用现有 sanitizer core/logging，接入 `async_pre_call_deployment_hook` 与 `log_pre_api_call`。
* `GlmCooldownAdapter` 实现 GLM 429 reset 时间解析、恢复时间计算与安全日志；运行时通过 failure hook 记录 cooldown，并在请求进入 Router 前把冷却中的 `cc-glmplan-*` 改写到对应 DeepSeek fallback。
* 配置层已迁移到统一 callback hub；旧单用途入口删除，避免 callback 顶层继续混杂实现细节。

## Decision (ADR-lite)

**Context**: LiteLLM callback 是全生命周期扩展点，单独挂载 `deepseek_thinking_sanitizer` 会把不同供应商兼容逻辑继续堆在单用途 callback 里；GLM cooldown 与 DeepSeek thinking sanitizer 的职责、触发阶段和状态需求不同。

**Decision**: 采用代码注册 adapter、配置只控制启用状态和策略参数的 `GatewayCallbackHub`。LiteLLM YAML 挂载统一 callback hub；DeepSeek sanitizer 与 GLM cooldown 作为独立 adapter 接入。

**Consequences**: 第一版配置稳定且容易测试；后续新增 provider-specific adapter 不需要改变 LiteLLM callback 挂载方式。代价是 adapter 列表不做完全 YAML 动态声明，如需新增 adapter 需要改 Python registry。

## Out of Scope

* 不改变 DeepSeek Claude Code 兜底路由的 thinking/effort 参数保留策略。
* 不处理非 GLM 供应商的动态冷却。
* 不在第一版引入跨容器共享状态，除非实现动态 cooldown 必须依赖数据库或外部缓存。

## Technical Notes

* 相关文件：
  * `ai/gateway/litellm/litellm.local.yaml`
  * `ai/gateway/litellm/newapi.yaml`
  * `ai/gateway/litellm/callbacks/gateway_callback.py`
  * `ai/gateway/litellm/callbacks/framework/hub.py`
  * `ai/gateway/litellm/callbacks/framework/adapters.py`
  * `ai/gateway/litellm/callbacks/adapters/deepseek/thinking_sanitizer.py`
  * `ai/gateway/litellm/callbacks/adapters/deepseek/thinking_sanitizer_core.py`
  * `ai/gateway/litellm/callbacks/adapters/glm/cooldown.py`
  * `ai/gateway/litellm/callbacks/tests/`
  * `ai/gateway/litellm/litellm.md`
  * `.trellis/spec/infra/litellm-gateway.md`
* Context7 使用 `/websites/litellm_ai` 查询 LiteLLM callback 与 Router 文档。
