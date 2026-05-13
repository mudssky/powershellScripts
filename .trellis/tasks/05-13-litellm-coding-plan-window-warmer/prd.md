# brainstorm: Coding Plan 额度窗口预热

## Goal

为智谱 Coding Plan 的 5 小时额度窗口设计一个“窗口预热/锁定”机制：在每天接近 8、13、18、23 点时主动发送一次轻量请求，让额度窗口尽量从这些时间段开始，减少正式工作时第一次请求意外开启窗口或撞上未恢复窗口的概率。

## What I already know

* 用户希望触发时间大致为每天 8、13、18、23 点，但不要整点发送，需要在 2 分钟内保持随机性。
* 用户建议发送类似“你好吗”的轻量请求，失败时可以重发一次。
* 用户曾倾向方案 A：在 `ai/gateway/litellm/compose.yaml` 中新增容器内 worker / sidecar，让启动 Compose 项目时自动生效。
* 用户进一步反馈：单独 worker / 容器可能太复杂，改动面偏大，需要重新收敛到更轻量的 MVP。
* 用户决定采用独立脚本方案；脚本发送预热请求前必须检测本机 LiteLLM Docker 已正常启动。
* 用户选择长期 watch 模式：脚本启动后常驻运行，自行等待并触发后续预热。
* 脚本需要支持窗口配置以适配多种套餐：一种按“指定开始时间 + 窗口时长”推导后续发送时间；另一种精确配置发送时间点。
* 用户最初希望尽量减少标准库之外的依赖；后续明确可以引入 LiteLLM SDK，并用 `uv` 安装和运行依赖。
* 用户不打算创建传统 venv 或独立 Python 项目；目标是一个可通过 `uv run --script` 直接运行的脚本工具。
* 本机 `python3 --version` 为 3.13.5，可使用标准库 `tomllib` 读取 TOML 配置。
* 脚本在宿主机运行，不进入容器；因此它不能天然随 Docker 容器启动，除非由 `start.ps1`、手动命令或宿主机计划任务显式启动。
* 用户倾向用 PM2 启动和管理长期脚本进程，方便查看日志、重启和开机恢复。
* 用户确认可以在仓库内放 PM2 ecosystem 配置文件。
* 脚本需要支持定义多个 Coding Plan warm；每个 plan 应可独立配置模型、prompt、调度模式、jitter 和重试策略。
* 当前 LiteLLM 网关已有 `callbacks.gateway_callback.proxy_handler_instance` 统一入口。
* 当前 callback hub 已包含 `GlmCooldownAdapter` 和 `DeepSeekThinkingSanitizerAdapter`，其中 GLM cooldown adapter 已负责从 429 错误中解析 reset 时间，并在冷却期把 `cc-glmplan-*` 请求切到 DeepSeek 兜底。
* `ai/gateway/litellm/litellm.local.yaml` 与 `newapi.yaml` 已配置 `cc-glmplan-opus` / `cc-glmplan-haiku`、DeepSeek fallback、2 次 429 短重试，以及 5 小时兜底冷却。
* `compose.yaml` 仅把 `callbacks/` 以只读目录挂载进 LiteLLM 容器，目前没有额外挂载长期状态目录或独立 sidecar 服务。
* LiteLLM 文档确认 Proxy 可以通过 `litellm_settings.callbacks` 注册自定义 callback；现有用法主要覆盖请求生命周期与日志事件。
* LiteLLM 文档存在相近的 `general_settings.background_health_checks` / `health_check_interval` 配置，可周期性做模型健康检查，但没有查到按固定时刻、随机 jitter、指定 prompt 的内建 cron 预热配置。
* 用户明确预热请求应该直连服务端点，而不是走本机 LiteLLM Proxy 转发，因为 LiteLLM 配置里有 fallback。
* 用户希望拆分脚本，避免单文件超过一千行。

## Assumptions (temporary)

* 预热请求应直连智谱 GLM Coding Plan 官方 OpenAI 兼容端点，不应经过 LiteLLM Proxy fallback 消耗兜底额度。
* 预热请求应尽量不输出 prompt、密钥、完整 headers 或完整请求体到日志。
* 预热工具是独立宿主机运维脚本，不绑定 LiteLLM callback 或 Compose 服务；LiteLLM 容器只可作为可选启动条件。
* 如果 LiteLLM 容器在计划时间没有运行，则本次预热可以跳过或由下一次容器启动后自然等待下个窗口。

## Open Questions

* 是否需要在未来支持配置热重载；MVP 可以要求修改 TOML 后重启 PM2 进程。

## Requirements (evolving)

* 每天在 8、13、18、23 点附近触发一次轻量 GLM Coding Plan 请求。
* 每次触发相对整点增加 0 到 120 秒随机偏移。
* 预热失败时最多重试 1 次。
* 预热失败不得影响普通 LiteLLM 请求链路。
* 行为必须可通过环境变量开关关闭，避免在不需要的环境里自动消耗额度。
* MVP 应尽量减少 `compose.yaml` 与 `start.ps1` 改动，除非确实需要独立进程隔离。
* 独立脚本发送请求前应支持可配置的前置检查：可选检查本机 Docker 中 `litellm` 容器处于 running 状态，并检查直连目标 API 健康端点可访问。
* 如果配置的容器或直连目标 API 未就绪，脚本不得发送预热请求，应输出清晰诊断并按运行模式等待或退出。
* 脚本默认以长期 watch 模式运行，启动后持续计算下一次预热时间并等待触发。
* 调度配置必须支持两种模式：
  * `interval`：配置首个开始时间与窗口时长，例如 `08:00` + `5h`，脚本自动推导同一天/跨天的后续触发时间。
  * `fixed_times`：直接配置每日精确发送时间点，例如 `08:00,13:00,18:00,23:00`。
* 配置必须支持多个 `[[plans]]`，每个 plan 独立配置 model、prompt、调度和重试；脚本合并所有 plan 的下一次触发时间统一调度。
* 两种调度模式都应叠加随机偏移窗口，默认整点后 `0-120` 秒。
* 调度计算应能跨天运行，避免 23 点之后无法正确计算次日首个窗口。
* 脚本使用 LiteLLM Python SDK 处理 OpenAI 兼容 completion 调用，通过 PEP 723 script metadata 和 `uv run --script` 管理依赖。
* 预热相关文件应集中放在 `ai/coding/window-warmer/`，避免堆在 LiteLLM 网关目录。
* 配置文件建议使用 TOML，例如 `ai/coding/window-warmer/window-warmer.toml`。
* 不创建 `requirements.txt`、`pyproject.toml` 或仓库级虚拟环境；脚本入口和模块化 helper 作为轻量工具维护。
* 启动方式采用 PM2 管理宿主机脚本，PM2 调用 `uv run --script`。
* 仓库内提供 PM2 ecosystem 配置文件，减少用户手写启动命令的概率。

## Acceptance Criteria (evolving)

* [ ] 可以配置启用/禁用预热功能，默认策略明确。
* [ ] 可以配置每日预热小时列表，默认覆盖 8、13、18、23。
* [ ] 调度会在每个目标整点后的 0 到 120 秒内触发一次预热请求。
* [ ] 单次预热失败时最多重试 1 次，并记录不含敏感信息的诊断日志。
* [ ] 预热请求直连上游服务端点，不通过现有 `cc-glmplan-* -> DeepSeek` fallback 消耗 DeepSeek 兜底。
* [ ] 方案改动面可控，不需要为了预热功能引入过多 Compose / 启动脚本复杂度。
* [ ] LiteLLM Docker 未运行时，脚本不会发送预热请求。
* [ ] 配置的 Docker 前置条件或直连 API 健康检查不通过时，脚本不会发送预热请求。
* [ ] `interval` 模式可由开始时间和窗口时长推导后续触发时间。
* [ ] `fixed_times` 模式可按每日时间点列表触发预热。
* [ ] 多个 `[[plans]]` 可以并存，且脚本会分别触发每个 plan 的预热请求。
* [ ] 长期 watch 模式可从当前时间计算下一次触发时间，并支持跨天。
* [ ] 脚本可以通过 `uv run --script ai/coding/window-warmer/window_warmer.py` 直接启动并自动准备 LiteLLM SDK 依赖。
* [ ] 文档提供 PM2 启动、查看日志、重启、停止和持久化命令。
* [ ] 仓库内 PM2 ecosystem 配置可直接启动默认 warmer。
* [ ] PM2 管理脚本时，脚本仍会在每次发送前检查配置的 Docker 前置条件和直连 API 健康端点。
* [ ] 离线测试覆盖时间计算、随机偏移边界、失败重试上限和禁用开关。

## Definition of Done (team quality bar)

* Tests added/updated (unit/integration where appropriate)
* Lint / typecheck / CI green
* Docs/notes updated if behavior changes
* Rollout/rollback considered if risky

## Out of Scope (explicit)

* 不尝试绕过或规避上游服务条款；该功能只按用户已有额度策略做低频轻量预热。
* 不在本任务中实现复杂额度仪表盘或历史统计。
* 不改变普通用户请求的 fallback 策略。
* 不通过 LiteLLM Proxy 发送预热请求；Proxy 只作为可选“本机网关已启动”检查对象。
* 不把 prompt、密钥、完整 headers 或完整请求体写入日志。

## Research References

* [`research/litellm-callback-scheduler.md`](research/litellm-callback-scheduler.md) — LiteLLM callback 适合请求生命周期改写；长期定时任务更适合独立调度或非常谨慎地在进程内启动后台任务。

## Research Notes

### What similar tools do

* 网关 callback 通常用于“某个请求正在发生时”的改写、日志、鉴权、监控和失败处理。
* 可靠定时任务通常由 cron、sidecar、systemd timer、容器内独立进程或外部调度器负责，因为它们不依赖业务请求触发生命周期，也更容易观察、重启和限权。

### Constraints from our repo/project

* 现有 callback hub 是单例对象，适合扩展 adapter，但当前抽象没有启动/关闭生命周期 hook。
* LiteLLM 容器可能有多 worker 或进程重启风险；如果在 callback import 时直接启动后台任务，可能出现重复调度或任务丢失。
* 现有 `GlmCooldownAdapter` 会在 `cc-glmplan-*` 冷却期把请求改写到 DeepSeek，因此预热请求如果走同一模型名，需要避免触发 fallback。
* `compose.yaml` 目前没有额外服务；增加 sidecar 会扩大运维面，但隔离性更清晰。

### Feasible approaches here

**Approach A: 独立 sidecar / 宿主机脚本直连上游 API**

* How it works: 新增一个轻量定时 worker 或 PowerShell/Node/Python 脚本，按 8/13/18/23 + 随机偏移调用智谱 GLM Coding Plan 官方端点。
* Pros: 调度生命周期独立，不污染请求 callback；更容易避免多 worker 重复；失败重试、日志和开关清晰。
* Cons: 需要新增 compose service 或启动脚本动作，部署面略增。
* Decision update: 用户认为单独 worker / 容器改动面可能过大，该方案暂不作为 MVP 首选。

**Approach B: 在 callback hub 进程内懒启动后台调度任务**

* How it works: callback 初始化时创建一个 asyncio 后台任务，定时直接调用上游或 LiteLLM 内部 completion。
* Pros: 文件集中在 `callbacks/`，用户最初提到的 callback 目录可承载。
* Cons: LiteLLM callback 文档主要面向请求生命周期；容器多 worker、热重载、import 多次时容易重复触发；缺少标准启动/关闭生命周期，稳定性和可测试性更差。
* MVP adjustment: 如果选择该方案，必须默认关闭，通过环境变量显式开启，并使用进程内单例/锁降低重复调度风险。

**Approach C: 不做主动预热，只增强 cooldown reset 后的首次探测**

* How it works: 继续依赖现有 429 reset 解析，在 reset 后下一次真实请求才探测 GLM。
* Pros: 完全不额外消耗额度，不新增调度。
* Cons: 无法把 5 小时窗口主动锁到 8/13/18/23；不满足用户核心目标。

**Approach D: 只新增手动预热命令 / 脚本**

* How it works: 新增一个 `start.ps1 warm-window` 或轻量脚本，手动发送一次预热请求；定时交给用户本机计划任务或暂不做。
* Pros: 改动最小，风险最低，便于先验证“预热请求真的能开启窗口”。
* Cons: 不能做到容器启动后自动定时，也不能完整满足每天 4 个时间点自动执行。
* Decision update: 用户选择独立脚本方向；脚本需要在发送前检测本机 `litellm` Docker 和 API 可用性。

**Approach E: 复用 LiteLLM background health checks**

* How it works: 在 `general_settings` 中启用 `background_health_checks: true`，通过 `health_check_interval` 设置周期性健康检查。
* Pros: 几乎不需要新增代码，属于 LiteLLM 内建能力。
* Cons: 它是固定间隔健康检查，不是按 8/13/18/23 固定时刻；不支持 0 到 120 秒随机偏移、指定“你好吗”prompt、失败只重发一次等窗口预热语义；若启用 shared health check 还需要 Redis。

## Technical Notes

* Inspected `.trellis/spec/infra/litellm-gateway.md`.
* Inspected `ai/gateway/litellm/callbacks/framework/hub.py`.
* Inspected `ai/gateway/litellm/callbacks/adapters/glm/cooldown.py`.
* Inspected `ai/gateway/litellm/callbacks/tests/test_glm_cooldown_adapter.py`.
* Inspected `ai/gateway/litellm/newapi.yaml`, `litellm.local.yaml`, `compose.yaml`.
* Inspected `ai/gateway/litellm/start.ps1`；当前 `up` 未点名服务，会启动全 Compose 项目，但 `apply` / `restart` / `logs` / `pull` 默认只操作 `litellm` 服务。
* Context7 LiteLLM lookup selected `/berriai/litellm`; docs show Proxy callback registration via `litellm_settings.callbacks` and custom `CustomLogger` hooks.
* Context7 Docker Compose lookup selected `/docker/compose`; docs confirm Compose 支持多服务定义、`depends_on` 与 `restart` 策略，restart 由 Docker Engine 执行。
* Context7 LiteLLM lookup selected `/websites/litellm_ai`; docs show `router_settings.allowed_fails` / `cooldown_time` / `retry_policy` 用于失败冷却与重试，`general_settings.background_health_checks` / `health_check_interval` 用于后台健康检查。

## Decision (ADR-lite)

**Context**: 预热任务需要长期定时运行，但不应污染 LiteLLM 请求 callback 生命周期，也不应依赖普通请求触发；同时用户反馈单独 worker / 容器可能改动过重。

**Decision**: 采用独立脚本方案，不新增 Compose sidecar，也不在 LiteLLM callback 内启动 scheduler。脚本负责调度/触发预热，并在每次发送前检查本机 LiteLLM Docker 与 API 可用性。

**Consequences**: 改动面集中在脚本与测试，避免影响 LiteLLM 主容器和 callback；长期 watch 模式让用户只需启动一次脚本，但需要可靠处理跨天调度、配置重载边界和进程退出。

## Scheduling Model

配置以多个 `[[plans]]` 为核心。每个 plan 表示一组需要预热的 Coding Plan / 模型入口，互相独立：

```toml
[[plans]]
name = "glm-coding-plan"
model = "GLM-5.1"
prompt = "你好吗"
schedule_mode = "fixed_times"
times = ["08:00", "13:00", "18:00", "23:00"]
jitter_seconds = 120
retry_count = 1
```

脚本会为所有启用 plan 计算下一次触发点，并按最早触发时间执行；如果多个 plan 在同一时间附近到期，会逐个发送，不共享请求状态。

### interval mode

配置一个基准开始时间和窗口时长，脚本从该时间开始按固定窗口长度推导后续预热时间。适合“套餐窗口固定为 N 小时，从第一次请求开始计时”的场景。

TOML 示例语义：

```toml
[schedule]
mode = "interval"
start_time = "08:00"
window = "5h"
jitter_seconds = 120
```

推导触发点：`08:00`、`13:00`、`18:00`、`23:00`、次日 `04:00` ...

### fixed_times mode

直接配置每日触发时间点。适合用户已经知道自己想锁定的时间段，或套餐窗口不适合用固定间隔推导的场景。

TOML 示例语义：

```toml
[schedule]
mode = "fixed_times"
times = ["08:00", "13:00", "18:00", "23:00"]
jitter_seconds = 120
```

MVP 实现中，`[[plans]]` 内使用 `schedule_mode`、`start_time`、`window`、`times` 表达调度；上方 `[schedule]` 示例只表达语义，实际配置以 `[[plans]]` 为准。

## Launch Options

**Option A: PM2 管理长期脚本（Recommended MVP）**

* 命令示例：`pm2 start ai/coding/window-warmer/window-warmer.pm2.config.cjs`
* 常用操作：`pm2 logs coding-window-warmer`、`pm2 restart coding-window-warmer`、`pm2 stop coding-window-warmer`、`pm2 save`。
* 优点：不创建仓库级 Python 项目；依赖由 `uv run --script` 准备；进程重启、日志、开机恢复交给 PM2。
* 缺点：需要用户本机已有 PM2 与 uv。

**Option B: 手动 / 前台运行**

* 命令：`uv run --script ai/coding/window-warmer/window_warmer.py --config ai/coding/window-warmer/window-warmer.toml`
* 优点：最少魔法，日志直接在终端可见，停止方式清晰。
* 缺点：用户需要单独启动这个脚本。

**Option C: `start.ps1 up --with-warmer` 后台启动**

* How it works: `start.ps1 up` 启动 LiteLLM 后再用宿主机 Python 拉起 warmer 后台进程。
* 优点：接近“随容器启动”的体验。
* 缺点：跨平台后台进程管理、重复启动检测、停止脚本和日志文件都会增加复杂度。

**Option D: 宿主机计划任务 / launchd / systemd user**

* How it works: 由系统登录项或计划任务启动长期 watch 脚本，脚本自己等待 LiteLLM 容器可用。
* 优点：最适合长期守护，不依赖终端。
* 缺点：需要按操作系统写少量配置说明，不属于脚本本身。
