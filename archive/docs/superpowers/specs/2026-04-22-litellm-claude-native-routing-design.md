# LiteLLM Claude Native Routing Design

## Summary

本设计调整 `ai/gateway/litellm` 中 Claude 系列模型的路由策略，把当前“Claude 模型也走 OpenAI 兼容上游”的配置，改为“Claude 默认走 Anthropic 原生上游”。

同时，为仍然需要通过 OpenAI 兼容客户端访问 Claude 的场景保留一组显式兼容别名：

- 默认原生模型名：`claude-opus-4-6`、`claude-opus-4-7`
- 兼容别名：`compat/claude-opus-4-6`、`compat/claude-opus-4-7`

这组兼容别名仍然指向同一个 Anthropic 原生上游，只是在 LiteLLM 对外暴露不同模型名，方便客户端和文档明确区分“默认原生路径”和“兼容调用路径”，避免再依赖上游执行 OpenAI -> Claude 的二次协议转换。

## Context

当前 `ai/gateway/litellm/litellm.local.yaml` 与 `ai/gateway/litellm/newapi.yaml` 中，Claude 模型使用了类似下面的路由方式：

```yaml
- model_name: "claude-opus-4-6"
  litellm_params:
    model: "openai/claude-opus-4-6"
    api_base: "os.environ/NEWAPI_API_BASE"
    api_key: "os.environ/NEWAPI_KEY"
```

这意味着：

- LiteLLM 会把 Claude 请求当成 OpenAI provider 请求处理
- 上游 `NEWAPI_API_BASE` 需要继续把 OpenAI 风格请求再转换成 Claude / Anthropic 风格
- 一旦上游不支持这类转换，就会出现 `convert_request_failed`、`not implemented` 一类错误

用户已经验证：

- 同一上游可被 `Claude Code` 直接使用
- 但通过当前 LiteLLM OpenAI 兼容链路访问 `claude-opus-4-6` 时会失败

这说明问题不在于“上游 Claude 模型不可用”，而在于“当前 LiteLLM -> 上游 的协议路径与上游真实支持能力不匹配”。

另外，用户补充了两个重要约束：

- 日常客户端大多兼容 Anthropic 协议
- Anthropic 链路不适合做过多非原生协议改写，避免兼容问题和额外风控不确定性

## Goals

- 让 Claude 默认路由改走 Anthropic 原生上游。
- 保留 OpenAI 兼容客户端访问 Claude 的能力，但使用单独别名，避免与默认原生模型名混淆。
- 让 `litellm.local.yaml` 与 `newapi.yaml` 保持一致，避免配置语义漂移。
- 保持当前 LiteLLM 对 GPT / Gemini / GLM 等其它模型的现有路由行为不变。
- 保持当前 `start.ps1 + compose.yaml + config.yaml` 的单入口工作流。

## Non-Goals

- 不把整个 LiteLLM 网关拆成两套独立服务。
- 不修改 GPT / Gemini / GLM 的上游路由策略。
- 不在第一版引入 team、access group 或多网关隔离。
- 不把 Claude 的兼容别名重新指回 `openai/claude-*` 这类需要上游二次转换的路径。
- 不承诺通过模型别名实现协议级硬隔离。

## Constraints

- 需要遵循当前 LiteLLM 目录的配置风格：通过 `compose.yaml` 注入环境变量，由 YAML 配置读取 `os.environ/...`。
- 需要让 `litellm.local.yaml` 与 `newapi.yaml` 采用一致的 Claude 路由语义。
- 需要兼顾 Anthropic 兼容客户端与 OpenAI 兼容客户端，但默认行为应优先偏向 Anthropic 原生路径。
- 需要接受一个现实限制：如果 LiteLLM 同时暴露 Anthropic 与 OpenAI 兼容入口，仅靠模型别名只能表达“推荐用法”，不能完全阻止客户端使用其它别名。

## Chosen Approach

采用“Claude 默认原生 + Claude 兼容别名共用同一 Anthropic 上游”的方案。

核心设计如下：

1. 把 `claude-opus-4-6`、`claude-opus-4-7` 从 `openai/...` 映射改为 `anthropic/...` 映射。
2. 新增 `compat/claude-opus-4-6`、`compat/claude-opus-4-7` 两个兼容别名。
3. 兼容别名也继续映射到同一个 `anthropic/...` 上游，而不是映射回 `openai/claude-*`。
4. 其它现有模型和全局 `* -> OpenAI / NewAPI` 兜底保持不变。

这样做的原因是：

- 默认模型名回到最接近真实协议的路径，稳定性更高。
- OpenAI 兼容客户端仍可通过 LiteLLM 的 OpenAI 接口访问这些兼容别名，由 LiteLLM 在本地完成协议适配。
- 不再依赖上游执行 OpenAI -> Claude 转换，能够直接避开当前 `convert_request_failed` 这类错误来源。
- 别名可以把“兼容调用是特例，不是默认推荐路径”表达得更清晰。

## Routing Design

第一版会把 Claude 路由拆成两组显式规则。

### Native Claude Routes

默认 Claude 模型名直接映射到 Anthropic provider：

```yaml
- model_name: "claude-opus-4-6"
  litellm_params: &newapi_anthropic_params
    model: "anthropic/claude-opus-4-6"
    api_base: "os.environ/NEWAPI_ANTHROPIC_API_BASE"
    api_key: "os.environ/NEWAPI_ANTHROPIC_KEY"

- model_name: "claude-opus-4-7"
  litellm_params:
    <<: *newapi_anthropic_params
    model: "anthropic/claude-opus-4-7"
```

### Compatibility Aliases

兼容别名仍然映射到同一个 Anthropic provider：

```yaml
- model_name: "compat/claude-opus-4-6"
  litellm_params:
    <<: *newapi_anthropic_params
    model: "anthropic/claude-opus-4-6"

- model_name: "compat/claude-opus-4-7"
  litellm_params:
    <<: *newapi_anthropic_params
    model: "anthropic/claude-opus-4-7"
```

设计意图如下：

- 默认模型名服务 Anthropic 原生使用场景。
- `compat/...` 仅作为命名约定，告诉调用方“这是给兼容客户端保留的入口”。
- 原生模型名和兼容别名都命中同一上游，避免功能表现因为别名而漂移。
- Claude 不再落到最后的 `* -> OpenAI / NewAPI` 路由。

## Environment Design

为了让 LiteLLM 容器能够读取 Claude 原生上游配置，需要新增两项环境变量：

- `NEWAPI_ANTHROPIC_API_BASE`
- `NEWAPI_ANTHROPIC_KEY`

它们的职责是：

- `NEWAPI_ANTHROPIC_API_BASE`：Claude 原生上游或 Anthropic 兼容入口地址
- `NEWAPI_ANTHROPIC_KEY`：对应上游的鉴权密钥

相应地，以下文件需要同步更新：

- `ai/gateway/litellm/compose.yaml`
- `ai/gateway/litellm/.env.example`
- `ai/gateway/litellm/.env.production.example`
- `ai/gateway/litellm/litellm.md`

如果当前上游地址已经包含完整 Anthropic 路径，实施时还需要确认是否应设置 `LITELLM_ANTHROPIC_DISABLE_URL_SUFFIX=true`。这属于实现期验证项，不改变本设计的总体结构。

## Request Flow

### Anthropic-Compatible Client

当 Anthropic 兼容客户端请求 `model=claude-opus-4-6` 时：

1. 请求进入 LiteLLM。
2. LiteLLM 命中 `claude-opus-4-6 -> anthropic/claude-opus-4-6` 规则。
3. LiteLLM 把请求发送到 `NEWAPI_ANTHROPIC_API_BASE`。
4. 上游按 Claude / Anthropic 原生协议处理并返回结果。

### OpenAI-Compatible Client

当 OpenAI 兼容客户端请求 `model=compat/claude-opus-4-6` 时：

1. 请求进入 LiteLLM 的 OpenAI 兼容入口。
2. LiteLLM 命中 `compat/claude-opus-4-6 -> anthropic/claude-opus-4-6` 规则。
3. LiteLLM 在本地完成 OpenAI 请求到 Anthropic provider 的适配。
4. 上游继续只接收 Anthropic 原生请求。

### Other Models

当客户端请求 GPT / Gemini / GLM 或其它非 Claude 模型时：

- 继续按当前显式模型或通配兜底规则处理
- 本次变更不改变这些路径的语义

## Naming Semantics

本设计使用别名前缀表达“推荐入口”，而不是试图做强制协议隔离。

约定如下：

- `claude-*`：默认原生入口
- `compat/claude-*`：兼容客户端入口

需要明确一点：

- 只要 LiteLLM 对外同时暴露多个协议入口，模型名本身不能从技术上阻止客户端调用另一个别名
- 因此，别名的主要价值是降低误用概率、提升文档可读性和排障清晰度
- 如果未来需要真正的硬隔离，应使用独立网关、独立 key 或 model access group，而不是继续依赖命名约定

## Error Handling

第一版保持最小行为增量，不为 Claude 路由额外引入复杂 fallback。

预期行为如下：

- 如果 `NEWAPI_ANTHROPIC_API_BASE` 或 `NEWAPI_ANTHROPIC_KEY` 缺失，Claude 请求直接返回配置或鉴权错误。
- 如果上游 Anthropic 兼容服务不可用，错误直接透出，不回退到 `* -> OpenAI / NewAPI`。
- 如果 OpenAI 兼容客户端请求 `compat/claude-*`，错误应来自 LiteLLM 本地适配或 Claude 原生上游，而不是上游的 OpenAI->Claude 转换层。
- `drop_params: true`、重试、超时等全局配置沿用当前 LiteLLM 设置。

## File Changes

第一版预计涉及以下文件：

- `ai/gateway/litellm/litellm.local.yaml`
- `ai/gateway/litellm/newapi.yaml`
- `ai/gateway/litellm/compose.yaml`
- `ai/gateway/litellm/.env.example`
- `ai/gateway/litellm/.env.production.example`
- `ai/gateway/litellm/litellm.md`

按职责划分：

- `litellm.local.yaml`：切换 Claude 默认路由并新增 `compat/claude-*`
- `newapi.yaml`：与本地配置保持同样的 Claude 路由结构
- `compose.yaml`：注入 `NEWAPI_ANTHROPIC_*` 环境变量
- `.env.example` / `.env.production.example`：补充 Claude 原生上游示例变量
- `litellm.md`：更新模型说明、环境变量说明与推荐调用方式

## Validation Strategy

优先采用“配置有效性 + 最小真实请求”两层验证。

### Config Validation

需要验证：

- `compose.yaml` 可以成功展开新增的 `NEWAPI_ANTHROPIC_*` 变量
- `litellm.local.yaml` 与 `newapi.yaml` 的 YAML 结构有效
- `/models` 返回中同时包含默认 Claude 名称与 `compat/claude-*` 别名

### Runtime Validation

最小运行时验证包括：

1. Anthropic 兼容客户端使用 `claude-opus-4-6` 发起最小请求并成功返回。
2. OpenAI 兼容客户端使用 `compat/claude-opus-4-6` 发起最小请求并成功返回。
3. 默认 `claude-opus-4-6` 请求不再出现 `convert_request_failed`。
4. 非 Claude 模型请求行为保持不变。

## Verification Plan

实现完成后的最小验收路径如下：

1. `docker compose --env-file ai/gateway/litellm/.env.local -f ai/gateway/litellm/compose.yaml --project-directory ai/gateway/litellm config` 成功展开配置。
2. `./ai/gateway/litellm/start.ps1 up` 能正常启动或重建容器。
3. `/models?return_wildcard_routes=true` 返回结果包含：
   - `claude-opus-4-6`
   - `claude-opus-4-7`
   - `compat/claude-opus-4-6`
   - `compat/claude-opus-4-7`
4. Anthropic 兼容最小请求可成功命中默认 Claude 模型。
5. OpenAI 兼容最小请求可成功命中 `compat/claude-*`。

如果本地没有可用的 Anthropic 上游密钥，至少应完成 compose 展开、容器启动和模型列表验证，并在实施说明中明确真实请求验证仍依赖上游可用凭证。

## Risks

- 如果当前 `NEWAPI_ANTHROPIC_API_BASE` 实际上并不是标准 Anthropic 兼容入口，而只是某个特定客户端可用的私有适配层，则 LiteLLM 的 Anthropic provider 仍可能需要额外细节调整。
- 模型别名只能表达推荐入口，不能替代硬隔离。
- 如果未来文档没有明确区分默认模型与兼容别名，调用方仍可能混用两条路径。

## Deferred Work

如后续需要，可在独立变更中继续考虑：

- 为 Claude 增加 `claude-*` 级别 wildcard 路由
- 为 Claude 原生与兼容流量增加独立 key 或 access group
- 为 Claude 增加专属 fallback 或多上游容灾
- 把不同客户端的调用示例拆成 Anthropic / OpenAI 两个独立小节

## References

- LiteLLM Anthropic provider 文档：<https://docs.litellm.ai/docs/providers/anthropic>
- LiteLLM 官方文档：<https://docs.litellm.ai/>
