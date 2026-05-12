# LiteLLM callback 与 Router 冷却调研

## 结论

* `litellm_settings.callbacks` 注册的是 LiteLLM Proxy 的调用生命周期 hook，不是只在 fallback 时触发。
* 本仓库的 `DeepSeekThinkingSanitizer` 在 hook 内部通过 `call_type == CallTypes.anthropic_messages` 与 DeepSeek deployment/model/api_base 判断是否实际清理；因此正常 GLM 请求会进入生命周期，但不会执行清理逻辑。
* `async_pre_call_deployment_hook` 是 Router 选中具体 deployment 后、provider 构造请求体前的请求改写点，适合做 DeepSeek fallback 的 messages 清理。
* `log_pre_api_call` 是 provider 发起 HTTP 请求前的 logging hook，可作为诊断与兜底，但不应作为唯一改写点。
* LiteLLM 文档暴露的 `cooldown_time` 是固定冷却时长；Context7 文档未显示可直接按 429 响应体里的重置时间动态设置 deployment cooldown 的 YAML 配置。
* 文档显示 Router 支持 `retry_policy`、`allowed_fails_policy`、`cooldown_time` 与 `retry_after`，但这些更像固定策略或重试等待，不等同于“解析上游错误 body 后冷却到指定时间”。

## 仓库现状

* `ai/gateway/litellm/litellm.local.yaml` 和 `ai/gateway/litellm/newapi.yaml` 中 `cc-glmplan-opus` / `cc-glmplan-haiku` 当前都配置 `cooldown_time: 3600`。
* 文档 `ai/gateway/litellm/litellm.md` 当前也说明 GLM 两个 Claude Code 入口失败后冷却 1 小时。
* `.trellis/spec/infra/litellm-gateway.md` 已要求 sanitizer 的触发边界以 Router 选中的目标部署是否为 DeepSeek Anthropic 兼容端点为准，而不是只依赖 `fallback_depth`。
* sanitizer 当前实现已经符合“不是只在 fallback 时清理，而是只在 DeepSeek Anthropic 请求上清理”的设计：直接调用 `claude-code-deepseek-*` 时同样受保护。

## 可行方案

### 方案 A：固定冷却改成 5 小时

* 做法：把两个 GLM Claude Code 入口的 `cooldown_time` 从 3600 改为 18000，并同步文档。
* 优点：实现最小，贴合 GLM 5 小时额度窗口，立刻减少中途多余探测请求。
* 缺点：如果 429 响应明确给出更早或更晚的恢复时间，固定 5 小时仍不够精确；也无法自然表达“恢复时间 + 1 分钟”。

### 方案 B：新增 GLM 429 重置时间感知逻辑

* 做法：在 LiteLLM 可用 hook 或本地兼容层中识别 GLM 429 错误体，解析 `您的限额将在 YYYY-MM-DD HH:mm:ss 重置`，按该时间加 60 秒设置后续请求避让。
* 优点：最贴近用户描述，能避免 GLM 窗口内重复探测，也能在额度提前恢复时及时切回。
* 缺点：需要确认 LiteLLM 当前运行版本是否有可写的 deployment cooldown API；如果没有，可能要通过外部缓存/请求前拦截实现，复杂度和回归风险更高。

### 方案 C：先固定 5 小时，同时预留动态解析测试

* 做法：本次先把 cooldown 改为 18000，文档明确这是临时保守策略；同时新增纯函数和测试，用于解析 GLM 429 reset 时间，后续接入 Router 冷却 API。
* 优点：兼顾当前止血和后续演进，测试先锁定中文错误格式。
* 缺点：会留下暂未接入运行链路的解析代码，除非下一步马上补齐动态冷却。

### 方案 D：统一 callback hub + 独立 adapter

* 做法：LiteLLM YAML 只挂载一个统一 `CustomLogger` 实例，由 hub 分发生命周期 hook；DeepSeek thinking sanitizer 与 GLM cooldown 都作为 adapter 接入。
* 优点：符合 callback 全生命周期扩展点的实际模型；不同供应商兼容逻辑可以独立启用、配置、测试。
* 缺点：需要先定义 adapter 协议、配置加载方式、异常隔离策略和安全日志边界。

## callback hub 设计建议

* 保持 LiteLLM 配置简单：`litellm_settings.callbacks` 中只挂载一个 hub。
* adapter 由 Python registry 管理，避免在 YAML 中直接散落多个 Python import 路径。
* 配置只负责声明 adapter 是否启用、适用范围和少量策略参数，例如：
  * `deepseek_thinking_sanitizer.enabled`
  * `glm_cooldown.enabled`
  * `glm_cooldown.model_groups`
  * `glm_cooldown.reset_buffer_seconds`
  * `glm_cooldown.fallback_cooldown_seconds`
* 每个 adapter 只实现自己需要的 hook；hub 对缺失 hook 自动跳过。
* adapter 默认 fail-open：记录安全日志，但不因为某个辅助逻辑失败拖垮请求链路。
* 对请求改写类 adapter，应明确 hook 阶段和可修改对象；例如 DeepSeek sanitizer 仍应在 `async_pre_call_deployment_hook` 做主改写。

## callback 问题回答

历史配置 `callbacks: - callbacks.deepseek_thinking_sanitizer.proxy_handler_instance` 表示 LiteLLM 启动时加载这个 `CustomLogger` 实例，并在请求生命周期对应阶段调用它实现的 hook。它不是 fallback 专用配置。当前实现已迁移到统一 `callbacks.gateway_callback.proxy_handler_instance`，再由 DeepSeek sanitizer adapter 通过以下条件缩小实际影响范围：

* `async_pre_call_deployment_hook` 只处理 `CallTypes.anthropic_messages`。
* `is_deepseek_anthropic_request(kwargs)` 必须识别到 DeepSeek 模型、DeepSeek deployment，或 DeepSeek Anthropic api_base。
* `fallback_depth` 只出现在日志诊断中，用于确认是否来自 Router fallback，不作为触发条件。

因此：正常 GLM 主路由不会被 sanitizer 清理；GLM 429 后 fallback 到 DeepSeek 会清理；用户直接调用 `claude-code-deepseek-*` 也会清理，因为同样是 DeepSeek Anthropic 请求。
