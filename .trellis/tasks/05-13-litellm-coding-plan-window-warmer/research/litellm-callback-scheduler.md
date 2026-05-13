# LiteLLM callback 与定时预热方案调研

## 问题

评估“每天在 8、13、18、23 点附近发送一次 GLM Coding Plan 轻量请求”是否适合放在 `ai/gateway/litellm/callbacks` 当前 callback 体系内。

## 代码库观察

当前 `ai/gateway/litellm` 采用 LiteLLM Proxy + 自定义 callback hub：

* `litellm_settings.callbacks` 注册 `callbacks.gateway_callback.proxy_handler_instance`。
* `GatewayCallbackHub` 继承 LiteLLM `CustomLogger`，分发 `async_pre_call_hook`、`async_pre_call_deployment_hook`、`async_log_failure_event` 和 `log_pre_api_call`。
* `GlmCooldownAdapter` 已在失败事件中解析 GLM 429 reset 时间，并在后续请求进入 Router 前把 `cc-glmplan-opus` / `cc-glmplan-haiku` 改写到 DeepSeek 兜底。
* `compose.yaml` 仅挂载 `./callbacks:/app/callbacks:ro`，没有额外挂载调度状态文件，也没有独立定时服务。

## LiteLLM 文档观察

Context7 查询 `/berriai/litellm` 后，文档示例显示：

* Proxy 配置可通过 `litellm_settings.callbacks` 注册 callback。
* 自定义 callback 常见用途是 cost tracking、成功/失败日志、外部观测系统集成。
* 示例基于 LiteLLM `CustomLogger` 的请求生命周期 hook。

这说明 callback 是已支持的扩展点，但它主要围绕已有请求发生时的生命周期，不天然提供 cron/worker 型调度生命周期。

Context7 查询 `/websites/litellm_ai` 后，还查到两类相关但不完全等价的配置：

* `router_settings.allowed_fails`、`cooldown_time`、`retry_policy`、`allowed_fails_policy`：用于请求失败后的重试、fallback 和部署冷却。
* `general_settings.background_health_checks: true`、`health_check_interval`、`use_shared_health_check`：用于后台模型健康检查；shared health check 需要 Redis 协调。

这些能力可以周期性探测模型状态，但没有看到按每天固定时刻触发、增加随机偏移、指定轻量 prompt、失败只重试一次的内建预热/cron 配置。

## 方案比较

### A. 独立 sidecar / 宿主机脚本直连上游 API（推荐）

优点：

* 调度生命周期独立，不依赖 LiteLLM callback import 时机。
* 可以避免多 worker / 热重载导致重复后台任务。
* 可以通过环境变量控制启用、目标小时、随机偏移、重试、模型名和 prompt。
* 可以把预热请求设计成直连 GLM Coding Plan 专用入口，避免进入 LiteLLM Proxy fallback。

缺点：

* 需要新增脚本或启动入口。
* 需要明确如何读取上游 `Z_AI_API_KEY`，以及是否把本机 LiteLLM 容器作为可选启动条件。

### B. callback hub 内懒启动后台任务

优点：

* 代码集中在现有 callback 目录。
* 可复用现有环境变量和容器网络。

风险：

* LiteLLM callback 没有显式启动/关闭生命周期抽象，import 时启动任务容易受多 worker、热重载和测试导入影响。
* callback 当前职责是请求改写、失败记录、兼容清洗；定时请求会把运维调度和请求生命周期混在一起。
* 如果后台任务异常，需要额外机制保证不影响主请求链路。

### C. 只增强现有 cooldown 探测

优点：

* 不新增主动请求，不额外消耗额度。
* 与当前 GLM 429 cooldown adapter 职责一致。

缺点：

* 不能主动把窗口锁定到 8、13、18、23，无法满足核心目标。

### D. 复用 LiteLLM background health checks

优点：

* 主要是配置改动，几乎不新增代码。
* 属于 LiteLLM 内建后台探测能力，语义上比 callback 自启动 scheduler 更接近“周期性任务”。

限制：

* `health_check_interval` 是固定间隔，不是每天指定时刻。
* 没有看到内建随机 jitter、指定 prompt、失败只重试一次的配置。
* shared health check 需要 Redis；本地单容器为了这个能力引入 Redis 会偏重。
* 需要实际确认健康检查对 Anthropic/GLM 上游发出的请求是否会开启 Coding Plan 额度窗口，以及请求体是否足够轻量。

## 推荐结论

从稳定性和职责边界看，预热调度不适合直接塞进现有 LiteLLM callback adapter 作为默认实现。更稳的 MVP 是独立脚本按计划直连智谱 GLM Coding Plan 专用入口；本机 LiteLLM 容器最多作为可选 readiness gate，避免 warm 请求进入 Proxy fallback 链路。

若用户强偏好“都放在 callback 目录”，也应把调度代码做成可禁用、单例保护、测试可注入时钟和随机数的后台 scheduler，并默认关闭，避免在生产/多 worker 下重复触发。

## 用户反馈后的收敛

用户反馈单独 worker / 容器可能太复杂，改动面偏大。因此后续 MVP 可以优先考虑：

* callback 内轻量 scheduler：保留“容器启动后自动生效”的体验，但必须默认关闭并通过环境变量显式开启。
* 手动预热命令：改动最小，先验证预热请求效果，但不解决自动定时。

## 最新收敛：独立脚本

用户决定采用独立脚本开发，不新增容器 worker，也不把 scheduler 放入 callback。后续又明确 warm 请求应直连服务端点，而不是走 LiteLLM Proxy 转发，因为 Proxy 已配置 fallback。最终脚本在发送预热请求前按配置确认：

* 可选：本机 Docker 中 `litellm` 容器存在且处于 running 状态，作为“本机网关已启动”的前置条件。
* 直连目标 API 可访问，例如智谱 Coding Plan `/models` 轻量端点返回成功。
* 只有上述条件满足后，才通过 LiteLLM Python SDK 直连上游发送 GLM Coding Plan 预热请求。

这种方案的改动面最集中，适合先验证预热策略；后续如果需要自动化，可以用 PM2、长期 watch 模式或系统计划任务来调用该脚本。

## 最终实现约束

* 文件位于 `ai/coding/window-warmer/`，不是 LiteLLM 网关子目录。
* 启动命令使用 `uv run --script ai/coding/window-warmer/window_warmer.py`，脚本元数据声明 `litellm` 依赖。
* PM2 配置调用 `uv run --script`，进程名为 `coding-window-warmer`。
* 默认 `[target].base_url` 指向 `https://open.bigmodel.cn/api/coding/paas/v4`，`api_key_env` 使用 `Z_AI_API_KEY`。
* 默认 plan 模型使用 `openai/GLM-5.1`，避免 LiteLLM SDK provider 推断歧义。
* 代码拆分为 `config`、`scheduler`、`target`、`runner`、`cli` 等模块，入口脚本保持薄封装。

## Compose 启动注意点

当前 `start.ps1 up` 生成 `docker compose up -d`，没有点名服务，因此新增 worker 后会随整个 Compose 项目启动。当前 `apply`、`restart`、`logs`、`pull` 默认只点名 `litellm`，如果希望“启动容器就能生效”的体验完整覆盖常用命令，实现时需要同步调整这些动作或文档中明确 worker 的操作方式。
