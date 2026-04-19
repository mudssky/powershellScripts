# LiteLLM GLM Coding Plan Design

## Summary

本设计为 `ai/gateway/litellm` 增加对智谱 `GLM Coding Plan` 的路由支持，但不替换当前 `Codex -> z.ai` 的直连配置。

第一版采用“显式主模型 + GLM 系列专属兜底”的结构：

- 显式暴露 `GLM-5.1`
- 为其它官方 `GLM-*` 模型保留同一上游的专属 fallback
- 继续保留当前全局 `* -> NewAPI` 兜底，不接管 GLM 路由

这样可以让 LiteLLM 成为其它 OpenAI 兼容客户端访问 GLM Coding Plan 的统一入口，同时保持仓库现有 `Codex` 工作流不受影响。

## Context

当前仓库里，`Codex` 侧已经在 `ai/coding/codex/config.toml` 中声明了 `model_providers.z_ai`，说明本地工作流已经具备直连智谱 Coding API 的能力。

但 `ai/gateway/litellm/litellm.local.yaml` 目前只显式注册了：

- `gpt-5.4`
- `gemini-3.1-pro`
- `claude-opus-4-6`
- 以及最后一条全局 `* -> NewAPI` 兜底

这意味着：

- `Codex` 可以直接走 `z.ai`
- 其它只会使用 OpenAI 兼容接口的客户端，如果希望通过本地 LiteLLM 访问 GLM Coding Plan，还没有现成路由
- 当前 `compose.yaml` 使用环境变量白名单注入容器，因此即使本地有对应密钥，如果不把变量加入白名单，LiteLLM 也无法在容器中读取 `os.environ/...`

同时，官方文档对接法有两个关键约束：

- GLM Coding Plan 需要走专属端点 `https://open.bigmodel.cn/api/coding/paas/v4`
- 模型名应沿用官方命名，如 `GLM-5.1`、`GLM-4.7`

## Goals

- 为 LiteLLM 增加可用的 GLM Coding Plan OpenAI 兼容路由。
- 保持官方模型命名，不新增仓库内部别名。
- 第一版稳定暴露 `GLM-5.1`，并支持其它 `GLM-*` 模型按同一路由规则转发。
- 不影响现有 `Codex` 直连 `z.ai` 的 provider 配置。
- 保持当前 `start.ps1 + compose.yaml + litellm.local.yaml` 的单入口工作流。

## Non-Goals

- 不修改 `ai/coding/codex/config.toml` 的默认 provider 选择。
- 不把 LiteLLM 改造成 z.ai 的唯一统一入口。
- 不在第一版显式列出全部 GLM 模型。
- 不新增第二套 LiteLLM compose 文件或第二个启动脚本。
- 不引入 GLM 专属的重试、超时、fallback 编排或多上游容灾。

## Constraints

- 需要遵循智谱官方 Coding Plan 专属端点与官方模型命名。
- 需要遵循当前 LiteLLM 目录的配置风格：通过 `compose.yaml` 白名单方式注入环境变量，由 `litellm.local.yaml` 读取 `os.environ/...`。
- 需要保持当前 `litellm.local.yaml` 的优先级语义，即越具体的规则越靠前、通配兜底越靠后。
- 需要继续区分“LiteLLM 已注册模型列表”和“上游实际可用模型列表”，避免文档误导。

## Chosen Approach

采用“在现有 `litellm.local.yaml` 内联扩展 GLM 路由”的方案。

具体结构如下：

1. 在现有显式模型之后、全局 `*` 之前插入 `GLM-5.1`。
2. 紧接着插入 `GLM-*` 规则，作为 GLM 系列专属兜底。
3. 保留当前最后一条全局 `* -> NewAPI` 规则不变。

这样形成的匹配优先级为：

- `GLM-5.1`
- `GLM-*`
- `*`

这个方案的优点是：

- 改动最小，完全复用当前目录结构和部署方式。
- `GLM-5.1` 可以稳定出现在 `/models` 中，适合作为文档和客户端接入的主入口。
- 其它 `GLM-*` 模型可以通过同一上游继承能力，避免每次都手动扩充显式列表。
- 非 GLM 模型的现有 NewAPI 路由行为完全不变。

之所以不采用“全部显式注册”或“另起一份独立 GLM 配置”，原因是：

- 全部显式注册会让后续维护成本快速上升。
- 独立配置文件会把当前单入口工作流拆成两套，增加文档、环境变量和运维复杂度。

## Routing Design

LiteLLM 中会新增两条与 GLM 相关的模型规则：

```yaml
- model_name: "GLM-5.1"
  litellm_params:
    model: "GLM-5.1"
    api_base: "os.environ/Z_AI_CODING_API_BASE"
    api_key: "os.environ/Z_AI_API_KEY"

- model_name: "GLM-*"
  litellm_params:
    model: "GLM-*"
    api_base: "os.environ/Z_AI_CODING_API_BASE"
    api_key: "os.environ/Z_AI_API_KEY"
```

设计意图如下：

- `model_name` 与 `litellm_params.model` 都保持官方命名，避免 LiteLLM 对外暴露名与上游真实模型名脱节。
- `GLM-5.1` 负责提供稳定、可见、文档友好的主模型入口。
- `GLM-*` 负责让其它同系列官方模型沿用同一路由策略。
- 全局 `*` 继续只兜底 NewAPI，不承担 GLM 请求。

这里有一个实现期需要验证的假设：

- `GLM-*` 这种 LiteLLM 路由写法在请求转发到智谱 Coding 端点时，能够按预期处理同系列官方模型名。

这是一个基于 LiteLLM 路由语义与智谱官方命名规则做出的合理推断。如果实际验证发现这条假设不成立，第一版的安全回退方案是收敛为“仅 `GLM-5.1` 显式路由”。

## Environment Design

为了让容器内的 LiteLLM 可以读取智谱相关配置，本设计引入以下环境变量：

- `Z_AI_API_KEY`
- `Z_AI_CODING_API_BASE`

推荐行为：

- `Z_AI_API_KEY` 由用户在 `.env.local` 中提供
- `Z_AI_CODING_API_BASE` 默认指向 `https://open.bigmodel.cn/api/coding/paas/v4`

选择单独引入 `Z_AI_CODING_API_BASE` 而不是把端点直接硬编码在 YAML 中，原因是：

- 与当前 `NEWAPI_API_BASE`、`DASHSCOPE_API_BASE` 的环境层抽象保持一致
- 用户在特殊网络、代理或未来上游迁移场景下更容易覆盖
- `compose.yaml` 的环境变量白名单职责更清晰

对应的 `compose.yaml` 需要把这两个变量加入 `environment` 白名单；否则 `litellm.local.yaml` 中的 `os.environ/...` 将无法在容器中解析。

## Data Flow

请求路径分为三类：

### GLM-5.1 显式主模型

当客户端请求 `model=GLM-5.1` 时：

1. LiteLLM 命中 `GLM-5.1` 显式规则。
2. 请求通过 `Z_AI_CODING_API_BASE` 转发到智谱 Coding 专属端点。
3. 使用 `Z_AI_API_KEY` 进行上游鉴权。
4. 结果原样返回给客户端。

### 其它 GLM 系列模型

当客户端请求其它官方 `GLM-*` 模型名时：

1. LiteLLM 不会命中 `GLM-5.1`。
2. 请求命中 `GLM-*` 系列兜底规则。
3. 请求继续转发到同一个智谱 Coding 专属端点。
4. 结果或错误原样返回给客户端。

### 非 GLM 模型

当客户端请求非 `GLM-*` 模型名时：

- 继续按当前逻辑命中显式模型或最后的全局 `* -> NewAPI`
- 本次设计不改变该路径的任何语义

## Error Handling

第一版保持“最小行为增量”原则，不为 GLM 引入额外的特殊恢复逻辑。

预期行为如下：

- 如果 `Z_AI_API_KEY` 缺失或无效，请求直接返回上游鉴权错误。
- 如果客户端请求的 `GLM-*` 模型在账号侧不可用，请求直接返回上游模型错误。
- 如果智谱上游超时、限流或其它请求失败，则沿用当前 LiteLLM 已配置的重试与超时策略。
- 如果 GLM 请求失败，不应回退到全局 `* -> NewAPI`，避免错误地切换到非智谱上游。

保留当前全局配置项：

- `drop_params: true`
- `num_retries: 2`
- `request_timeout: 60`
- Router 级 `num_retries` 与 `timeout`

这样可以让 GLM 路由在行为上尽量贴近当前网关整体语义，而不是引入一套新的例外规则。

## File Changes

第一版预计涉及以下文件：

- `ai/gateway/litellm/litellm.local.yaml`
- `ai/gateway/litellm/compose.yaml`
- `ai/gateway/litellm/.env.example`
- `ai/gateway/litellm/.env.production.example`
- `ai/gateway/litellm/litellm.md`

按职责划分：

- `litellm.local.yaml`：新增 GLM 显式路由与系列兜底
- `compose.yaml`：新增 `Z_AI_*` 环境变量白名单注入
- `.env.example` / `.env.production.example`：补充智谱相关配置示例
- `litellm.md`：说明新增 GLM 路由、环境变量和 `/models` 预期行为

## Validation Strategy

本设计优先采用“配置有效性 + 最小真实请求”两层验证。

### Config Validation

使用 `docker compose ... config` 验证：

- 新增环境变量不会破坏 compose 模板解析
- `compose.yaml` 能正确把 `Z_AI_API_KEY` 与 `Z_AI_CODING_API_BASE` 注入容器
- `litellm.local.yaml` 与挂载路径保持兼容

### Runtime Validation

在容器启动后验证：

1. `/models?return_wildcard_routes=true` 中能看到 `GLM-5.1`
2. 现有 `gpt-5.4`、`gemini-3.1-pro`、`claude-opus-4-6` 和全局 `*` 仍保留
3. `model=GLM-5.1` 的最小请求可以命中智谱 Coding 端点
4. 另一个 `GLM-*` 官方模型名请求可以命中 GLM 系列兜底
5. 若该模型不可用，错误应直接来自智谱上游，而不是误落到 `* -> NewAPI`

## Verification Plan

实现完成后的最小验收路径如下：

1. `docker compose --env-file ai/gateway/litellm/.env.local -f ai/gateway/litellm/compose.yaml --project-directory ai/gateway/litellm config` 成功展开配置。
2. `./ai/gateway/litellm/start.ps1 up` 能正常启动或重建容器。
3. 调用 `/models?return_wildcard_routes=true` 时，返回结果包含 `GLM-5.1`。
4. 发起 `model=GLM-5.1` 的最小请求时，请求能被转发到智谱 Coding 端点。
5. 发起另一个 `GLM-*` 官方模型请求时，若上游支持则成功返回；若不支持，则返回上游错误，不切换到 NewAPI。

如果本地环境无法完成真实上游请求验证，至少应完成配置展开与容器启动验证，并在实施说明中明确剩余验证依赖真实 `Z_AI_API_KEY` 与账号模型权限。

## Risks

- `GLM-*` 规则能否与智谱 Coding 端点完美配合，需要通过真实请求验证。
- LiteLLM `/models` 只反映已注册模型与通配规则，不等于上游全部可用模型列表。
- 如果用户误以为 LiteLLM 已经成为 `Codex` 的默认 GLM 入口，可能产生使用预期偏差，因此文档必须明确“Codex 直连保持不变”。

## Deferred Work

如后续需要，可在独立变更中继续考虑：

- 为更多常用 GLM 模型增加显式注册
- 为智谱与 NewAPI 增加更细粒度的渠道别名
- 为 GLM 路由引入专属 fallback 或多上游容灾
- 在文档中补充不同客户端接入 GLM Coding Plan 的示例

这些内容都不属于本次首版设计范围。

## References

- 智谱 Coding Plan 官方文档：<https://docs.bigmodel.cn/cn/coding-plan/tool/others>
- 智谱 Cursor 接入文档：<https://docs.bigmodel.cn/cn/coding-plan/tool/cursor>
- LiteLLM 官方文档：<https://docs.litellm.ai/>
