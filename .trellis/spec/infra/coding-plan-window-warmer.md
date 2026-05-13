# Coding Plan Window Warmer Spec

> 本规范记录 `ai/coding/window-warmer` 的预热调度、直连上游、依赖管理和 PM2 管理约定。修改窗口预热工具、默认 TOML、PM2 配置或相关启动文档时必须先阅读。

---

## Scenario: Direct Coding Plan Window Warmup

### 1. Scope / Trigger

- Trigger: 修改 `ai/coding/window-warmer/**`、窗口预热启动命令、默认 `window-warmer.toml`、PM2 ecosystem 配置，或 LiteLLM 网关文档中的窗口预热说明。
- Scope: 宿主机侧独立脚本按多个 `[[plans]]` 的 `fixed_times` 或 `interval` 调度发送轻量 completion 请求，用于把 Coding Plan 额度窗口尽量锁定到可预期的时间段。
- Design intent: 预热是独立运维工具，不属于 LiteLLM callback、LiteLLM Proxy 路由或 Docker Compose sidecar；默认请求必须直连上游 Coding Plan 服务端点，避免被 LiteLLM Proxy fallback 到 DeepSeek 或其它兜底路由。

### 2. Signatures

- Direct run:
  - From `ai/coding/window-warmer`: `uv run python window_warmer.py --config window-warmer.toml`
  - From `ai/coding/window-warmer`: `uv run python window_warmer.py --config window-warmer.toml --print-next`
  - From `ai/coding/window-warmer`: `uv run python window_warmer.py --config window-warmer.toml --once --dry-run`
- PM2:
  - `pm2 start ai/coding/window-warmer/window-warmer.pm2.config.cjs`
  - PM2 app name: `coding-window-warmer`
- Python script:
  - Entry file: `ai/coding/window-warmer/window_warmer.py`
  - Dependency declaration: `ai/coding/window-warmer/pyproject.toml`
  - Locked dependencies: `ai/coding/window-warmer/uv.lock`
  - Helper package: `ai/coding/window-warmer/window_warmer_lib/`

### 3. Contracts

- Target config `[target]`:
  - `name`: log-only target name.
  - `base_url`: direct upstream OpenAI-compatible API base URL. Default points to `https://open.bigmodel.cn/api/coding/paas/v4`, not local LiteLLM Proxy.
  - `container_name`: optional local Docker readiness gate. When set to `litellm`, it only proves the local gateway container is running; it must not change the warm request destination.
  - `api_key_env`: optional environment variable for upstream API key. Default for Z.ai Coding Plan is `Z_AI_API_KEY`.
  - `env_file`: optional dotenv file path, resolved relative to the TOML file. Default is `.env.local` in the warmer directory.
  - `health_path`: optional direct target health path. Default is `/models`.
  - `request_timeout_seconds`: timeout used by health check and LiteLLM SDK completion.
- Plan config `[[plans]]`:
  - `model`: LiteLLM SDK model string. For direct OpenAI-compatible upstreams, use `openai/<provider-model>`, for example `openai/GLM-5.1`.
  - `prompt`: light warmup prompt. Logs must not print prompt text.
  - `schedule_mode`: `fixed_times` or `interval`.
  - `times`: required for `fixed_times`.
  - `start_time` or `start_at` plus `window`: required for `interval`.
  - `jitter_seconds`, `retry_count`, `retry_delay_seconds`: per-plan overrides.
- Request contract:
  - Warm requests use `litellm.completion(model=plan.model, messages=[...], api_base=target.base_url, api_key=api_key, timeout=..., max_tokens=..., temperature=...)`.
  - The warmer must not call local LiteLLM Proxy `/v1/chat/completions` for default GLM warmup.
  - Health checks may use direct HTTP GET because they are a readiness probe, not the warmup completion.

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| `scheduler.enabled=false` | Script exits successfully without scheduling warmups |
| No enabled plans | `--once` / watch mode logs `没有启用的 plan` and does not send requests |
| `container_name` configured but Docker missing | Warmup is skipped with `未找到 docker 命令` diagnostic |
| `container_name` configured but container not running | Warmup is skipped before reading/sending completion |
| `api_key_env` configured but missing from env and `env_file` | Warmup is skipped with missing key diagnostic |
| `health_path` configured but direct target health check fails | Warmup is skipped before completion request |
| `--dry-run` or `scheduler.dry_run=true` | Docker/API readiness checks and completion request are skipped |
| LiteLLM SDK completion fails | Failure is logged without prompt/key/body; retry up to `retry_count` |
| Multiple plans share the same base time | Each plan remains in the event queue and is executed independently |

### 5. Good/Base/Bad Cases

- Good: Default config checks optional local `litellm` container but sends `openai/GLM-5.1` to `https://open.bigmodel.cn/api/coding/paas/v4` through LiteLLM SDK.
- Good: `uv add litellm` records the direct dependency in tool-local `pyproject.toml` and locks it in `uv.lock`; `uv run` syncs the environment before execution.
- Good: Put real API keys in ignored `.env.local`; commit only `.env.example`.
- Good: Time calculation is pure and unit-tested separately from HTTP/LiteLLM SDK calls.
- Base: `fixed_times = ["08:00", "13:00", "18:00", "23:00"]` with `jitter_seconds = 120` schedules each event within two minutes after the base time.
- Bad: Pointing `[target].base_url` at `http://127.0.0.1:34000` for default GLM warmup, because the request can enter LiteLLM Proxy fallback chains.
- Bad: Using model `GLM-5.1` without an explicit provider prefix for direct upstream calls, because LiteLLM SDK provider inference can be ambiguous.
- Bad: Logging prompt text, API key, full headers, or full request body.
- Bad: Re-merging all helper modules into a single thousand-line script.

### 6. Tests Required

- Unit tests for `fixed_times` next-day rollover.
- Unit tests for `interval` continuous-window rollover across midnight.
- Unit tests for multiple plans with simultaneous base time remaining independently executable.
- Config parse tests for multiple `[[plans]]`.
- SDK call test mocking the local wrapper around `litellm.completion`, asserting:
  - `model` keeps the configured provider-prefixed model.
  - `api_base` is the direct target URL.
  - prompt, max tokens, temperature and timeout are passed.
- Dry-run test asserting readiness checks are skipped.
- Smoke commands:
  - From `ai/coding/window-warmer`: `uv run python window_warmer.py --config window-warmer.toml --print-next`
  - From `ai/coding/window-warmer`: `uv run python window_warmer.py --config window-warmer.toml --once --dry-run`
  - `node -c ai/coding/window-warmer/window-warmer.pm2.config.cjs`

### 7. Wrong vs Correct

#### Wrong

```toml
[target]
name = "local-litellm"
base_url = "http://127.0.0.1:34000"
api_key_env = "LITELLM_MASTER_KEY"
health_path = "/health"

[[plans]]
model = "GLM-5.1"
endpoint = "/v1/chat/completions"
```

问题：这会把 warmup 请求送进 LiteLLM Proxy；如果 GLM 429 或被 callback 标记冷却，请求可能 fallback 到 DeepSeek，既不能锁定 GLM Coding Plan 窗口，也会消耗兜底额度。

#### Correct

```toml
[target]
name = "z-ai-coding-plan"
base_url = "https://open.bigmodel.cn/api/coding/paas/v4"
container_name = "litellm"
api_key_env = "Z_AI_API_KEY"
env_file = ".env.local"
health_path = "/models"

[[plans]]
name = "glm-coding-plan"
model = "openai/GLM-5.1"
schedule_mode = "fixed_times"
times = ["08:00", "13:00", "18:00", "23:00"]
```

理由：`container_name` 只是可选本机启动条件；真实 warmup completion 由 LiteLLM SDK 直连 `target.base_url`，不会进入 LiteLLM Proxy 路由/fallback。
