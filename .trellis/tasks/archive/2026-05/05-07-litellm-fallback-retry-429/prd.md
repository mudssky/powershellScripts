# LiteLLM Claude Code GLM 入口 429 无感 fallback

## Goal

让 `ai/gateway/litellm/litellm.local.yaml` 中 Claude Code GLM 主入口在上游返回 429 或临时限流时，优先由 LiteLLM 网关重试并按既有 fallback 路由切到 DeepSeek 备用上游，尽量让 Claude Code / 前端客户端感知不到瞬时 429。

## What I already know

* 用户希望 `ai/gateway/litellm/litellm.local.yaml` 在 fallback 的时候顺便重试，并“把 429 的请求覆盖让前端感知不到”。
* 当前本地配置已经存在 `litellm_settings.num_retries: 2` 和 `router_settings.num_retries: 2`。
* 当前 fallback 只覆盖 `cc-glmplan-opus -> claude-code-deepseek-v4-pro` 与 `cc-glmplan-haiku -> claude-code-deepseek-v4-flash`。
* 当前 GLM Claude Code 入口设置了 `cooldown_time: 3600`，用于失败后冷却再恢复探测。
* `qwen.yaml` 和 `docs/multi-newapi-routing.md` 已有固定模型 fallback 示例。
* LiteLLM 官方文档把 429 归入 `RateLimitError`，普通 `fallbacks` 可覆盖该错误；fallback 会在当前模型重试耗尽后触发。
* `router_settings.retry_policy.RateLimitErrorRetries` 可以显式声明 429 重试次数，避免只靠读者理解全局 `num_retries`。
* 当前其它显式模型没有备用 deployment/model；仅配置重试不能隐藏持续 429，本任务不扩展这些模型。

## Requirements

* 本任务优先通过 LiteLLM YAML 配置解决，不新增代理服务或自定义中间层。
* 只处理 Claude Code GLM 入口：`cc-glmplan-opus` 和 `cc-glmplan-haiku`。
* LiteLLM 本地配置需要对 Claude Code GLM 入口的 429 / RateLimitError 执行网关内短重试。
* GLM 入口重试失败后应按既有 fallback 路由切到 DeepSeek 备用上游，避免客户端立即收到 429。
* 不改变 Claude Code 客户端传入的模型名和调用方式。
* 配置注释需说明 retry、fallback、cooldown 的设计意图。
* 对全部重试和 fallback 都失败的情况，文档需明确仍会向客户端返回错误。

## Acceptance Criteria

* [ ] `litellm.local.yaml` 中 429 相关重试 / fallback 配置语义明确，并与 LiteLLM 官方行为一致。
* [ ] `cc-glmplan-opus` 遇到 429 时会尝试重试，仍失败后 fallback 到 `claude-code-deepseek-v4-pro`。
* [ ] `cc-glmplan-haiku` 遇到 429 时会尝试重试，仍失败后 fallback 到 `claude-code-deepseek-v4-flash`。
* [ ] 文档更新说明 429 被网关吸收的边界：全部重试和 fallback 都失败时仍会向客户端暴露错误。
* [ ] YAML 能被解析，基础 QA 通过。

## Definition of Done (team quality bar)

* Tests added/updated where behavior can be validated locally.
* Lint / typecheck / CI green where applicable.
* Docs/notes updated if behavior changes.
* Rollout/rollback considered if risky.

## Out of Scope (explicit)

* 不新增新的 LiteLLM 上游供应商或新依赖。
* 不为 `gpt-5.5`、`gemini-3.1-pro`、`compat/claude-*`、`GLM-*`、`*` 等普通模型新增 429 备用部署。
* 不承诺无限重试或完全吞掉持续性额度耗尽。
* 不修改前端客户端代码。

## Research References

* [`research/litellm-retry-fallback-429.md`](research/litellm-retry-fallback-429.md) — 确认 LiteLLM 429 会走 `RateLimitError` retry/fallback 语义，并整理推荐配置边界。

## Research Notes

### Feasible approaches here

**Approach A: 显式化现有 Claude Code 429 策略（Recommended）**

* How it works: 保留现有 GLM -> DeepSeek fallback，补充 `retry_policy.RateLimitErrorRetries` 与文档说明。
* Pros: 改动小，不改变客户端模型名，不新增上游或依赖，直接解决当前 GLM 限流场景。
* Cons: 只对已有备用模型的 Claude Code 入口真正无感；其它模型持续 429 仍可能暴露。

**Approach B: 为更多显式模型新增备用部署**

* How it works: 为 `gpt-5.5`、`gemini-3.1-pro`、`compat/claude-*` 等配置备用 model/deployment，再通过 `fallbacks` 或 `order` 路由吸收 429。
* Pros: 覆盖范围更广，普通前端模型也能更少看到 429。
* Cons: 需要更多上游凭据、命名与成本策略，配置复杂度明显增加。

**Approach C: 提高全局重试次数**

* How it works: 增大 `num_retries` 或 429 retry 次数，给同一上游更多恢复机会。
* Pros: 最少配置改动。
* Cons: 持续限流时只会放大等待时间，不能切换到健康备用上游，不适合交互式前端/Claude Code。

## Decision (ADR-lite)

**Context**: 用户确认本次只做 Claude Code GLM 入口的 429 无感 fallback，其它模型没有备用 deployment，扩大范围会引入更多上游凭据、成本和路由策略问题。

**Decision**: 采用 Approach A。保留 `cc-glmplan-opus/haiku` 的现有 DeepSeek fallback，显式补充 429 / `RateLimitError` retry 策略与文档边界说明。

**Consequences**: Claude Code GLM 入口的瞬时 429 更可能被网关内 retry/fallback 吸收；普通模型的持续 429 不在本任务中隐藏，未来若需要覆盖需先新增备用上游。

## Technical Approach

* 在 `router_settings` 中显式配置 429 / `RateLimitError` 的短重试策略，保持整体交互延迟可控。
* 保留现有 `fallbacks`：`cc-glmplan-opus -> claude-code-deepseek-v4-pro`、`cc-glmplan-haiku -> claude-code-deepseek-v4-flash`。
* 保留 GLM deployment 的 `cooldown_time: 3600`，继续按额度耗尽/限流后的冷却策略恢复探测。
* 更新 `litellm.md`，说明 429 先短重试、再 fallback 到 DeepSeek，且全部路径失败后仍会返回错误。

## Implementation Plan

* PR1: 更新 `litellm.local.yaml` 的 Router 429 retry 策略与中文注释。
* PR2: 更新 `litellm.md` 的 Claude Code GLM fallback 说明与失败边界。
* PR3: 运行 YAML 解析与项目 QA，确认配置文件格式有效。

## Technical Notes

* Inspected `ai/gateway/litellm/litellm.local.yaml`.
* Inspected `ai/gateway/litellm/qwen.yaml`.
* Inspected `ai/gateway/litellm/newapi.yaml`.
* Inspected `ai/gateway/litellm/docs/multi-newapi-routing.md`.
* Inspected `ai/gateway/litellm/litellm.md`.
