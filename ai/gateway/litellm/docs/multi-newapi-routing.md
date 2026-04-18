# LiteLLM 多 NewAPI / 多渠道配置方案

这份文档用于说明：当 LiteLLM 需要同时接入多个 NewAPI 上游时，可以采用哪些配置方式，以及每种方式的优缺点、适用场景和最小配置示例。

主入口说明见 [litellm.md](/Users/mudssky/projects/powershellScripts/ai/gateway/litellm/litellm.md)，兼容性与已知限制见 [litellm.notes.md](/Users/mudssky/projects/powershellScripts/ai/gateway/litellm/litellm.notes.md)。

## 目标

这里的“多 NewAPI / 多渠道”主要覆盖以下几类需求：

- 不同模型族走不同 NewAPI
- 同一个模型挂多个 NewAPI 做主备或容灾
- 对外暴露不同渠道名或别名
- 不同团队或租户走不同 NewAPI
- 把以上能力混合起来，但尽量保持配置可维护

## 术语约定

- `NewAPI`：OpenAI 兼容上游网关
- `LiteLLM model_name`：LiteLLM 对外暴露给客户端的模型名
- `litellm_params.model`：LiteLLM 实际转发给上游的模型名
- `渠道`：人为定义的路由名、别名或上游分组名，例如 `stable/gpt-5.4`
- `fallback`：主路由失败后切到备用路由
- `wildcard`：使用 `*` 做模型名匹配，例如 `gpt-*`

## 方案总览

| 方案 | 核心思路 | 复杂度 | 优点 | 缺点 | 适用场景 |
| --- | --- | --- | --- | --- | --- |
| A | 按模型显式绑定多个 NewAPI | 低 | 最直观，排障容易 | 模型多了维护重 | 常用模型固定、优先求稳 |
| B | 按模型族 wildcard 分流 | 中 | 新模型可自动继承规则 | 匹配顺序需要小心 | OpenAI/Gemini/Claude 命名规则稳定 |
| C | 显式主模型 + wildcard fallback | 中 | 常用模型清晰，列表外模型还能透传 | `/models` 会出现 `*` | 想兼顾“固定主模型”与“临时试新模型” |
| D | 同模型多 NewAPI 主备 / 容灾 | 中 | 同模型可自动切备 | 路由命名会更复杂 | 上游稳定性不一致，需要容灾 |
| E | 渠道 / 别名路由 | 中 | 客户端可明确选择不同渠道 | 需要统一命名规范 | 想区分 `stable`、`lowcost`、`backup` 等渠道 |
| F | 按 team / tenant 路由 | 高 | 多租户隔离能力强 | 依赖 LiteLLM key/team 体系 | 团队间需要独立上游或独立配额 |
| G | 混合架构 | 高 | 最灵活 | 最难维护 | 同时需要模型分流、容灾与租户隔离 |

## 方案 A：按模型显式绑定多个 NewAPI

这是最推荐的起步方案。

思路：

- 为每个上游 NewAPI 准备一组独立的环境变量
- 在 `model_list` 中把每个模型显式绑定到某一个 NewAPI
- 客户端只关心 LiteLLM 暴露出来的稳定模型名

### 优点

- 配置最直观
- `/models` 返回结果最清晰
- 发生问题时最容易定位到具体上游

### 缺点

- 每增加一个模型都要手动改配置
- 模型数量多时，`model_list` 会比较长

### `.env.local` 示例

```dotenv
NEWAPI_OPENAI_API_BASE=http://newapi-openai.example.com/v1
NEWAPI_OPENAI_KEY=sk-openai-route

NEWAPI_GOOGLE_API_BASE=http://newapi-google.example.com/v1
NEWAPI_GOOGLE_KEY=sk-google-route

NEWAPI_ANTHROPIC_API_BASE=http://newapi-anthropic.example.com/v1
NEWAPI_ANTHROPIC_KEY=sk-anthropic-route

LITELLM_MASTER_KEY=sk-litellm-xxxx
```

### `litellm.local.yaml` 示例

```yaml
model_list:
  - model_name: "gpt-5.4"
    litellm_params:
      model: "openai/gpt-5.4"
      api_base: "os.environ/NEWAPI_OPENAI_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_KEY"

  - model_name: "gemini-3.1-pro"
    litellm_params:
      model: "openai/gemini-3.1-pro"
      api_base: "os.environ/NEWAPI_GOOGLE_API_BASE"
      api_key: "os.environ/NEWAPI_GOOGLE_KEY"

  - model_name: "claude-opus-4-6"
    litellm_params:
      model: "openai/claude-opus-4-6"
      api_base: "os.environ/NEWAPI_ANTHROPIC_API_BASE"
      api_key: "os.environ/NEWAPI_ANTHROPIC_KEY"
```

## 方案 B：按模型族 wildcard 分流

思路：

- 不再逐个模型显式配置，而是按命名模式做分流
- 例如 `gpt-*` 走 OpenAI 上游，`gemini-*` 走 Google 上游，`claude-*` 走 Anthropic 上游

### 优点

- 新增同模型族时通常不用改配置
- 比纯显式配置更省维护成本

### 缺点

- 匹配顺序要稳定，越具体的规则要放越前面
- `/models` 不会自动变成“上游完整模型清单”
- 如果不同上游都有同名模型，会变得更难解释

### `litellm.local.yaml` 示例

```yaml
model_list:
  - model_name: "gpt-*"
    litellm_params:
      model: "openai/gpt-*"
      api_base: "os.environ/NEWAPI_OPENAI_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_KEY"

  - model_name: "gemini-*"
    litellm_params:
      model: "openai/gemini-*"
      api_base: "os.environ/NEWAPI_GOOGLE_API_BASE"
      api_key: "os.environ/NEWAPI_GOOGLE_KEY"

  - model_name: "claude-*"
    litellm_params:
      model: "openai/claude-*"
      api_base: "os.environ/NEWAPI_ANTHROPIC_API_BASE"
      api_key: "os.environ/NEWAPI_ANTHROPIC_KEY"
```

## 方案 C：显式主模型 + wildcard fallback

这是当前本地配置已经采用的思路扩展版。

思路：

- 常用模型显式注册，让 `/models` 结果稳定
- 末尾保留一条或多条 wildcard 作为兜底
- 显式模型优先命中，列表外模型再走 fallback

### 优点

- 常用模型清楚可见
- 试用新模型时不一定要立刻改配置

### 缺点

- `/models` 会出现 `*` 或其它 wildcard 路由
- 读者需要理解“显式模型列表”和“上游透传能力”不是一回事

### `litellm.local.yaml` 示例

```yaml
model_list:
  - model_name: "gpt-5.4"
    litellm_params:
      model: "openai/gpt-5.4"
      api_base: "os.environ/NEWAPI_OPENAI_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_KEY"

  - model_name: "gemini-3.1-pro"
    litellm_params:
      model: "openai/gemini-3.1-pro"
      api_base: "os.environ/NEWAPI_GOOGLE_API_BASE"
      api_key: "os.environ/NEWAPI_GOOGLE_KEY"

  - model_name: "claude-opus-4-6"
    litellm_params:
      model: "openai/claude-opus-4-6"
      api_base: "os.environ/NEWAPI_ANTHROPIC_API_BASE"
      api_key: "os.environ/NEWAPI_ANTHROPIC_KEY"

  - model_name: "*"
    litellm_params:
      model: "openai/*"
      api_base: "os.environ/NEWAPI_OPENAI_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_KEY"
```

### 适合当前仓库的场景

- 常用大模型需要清晰固定暴露
- 偶尔还想透传上游新增模型
- 不想为每个临时模型都改一轮配置

## 方案 D：同模型多 NewAPI 主备 / 容灾

思路：

- 同一个业务模型挂两个或多个不同 NewAPI
- 主模型失败后自动 fallback 到备用模型
- 对客户端仍然只暴露一个主模型名

### 优点

- 最适合解决单个上游波动或限流问题
- 客户端模型名可以保持稳定

### 缺点

- 配置需要额外引入“内部备用模型名”
- 路由拓扑比纯显式绑定复杂

### `litellm.local.yaml` 示例

```yaml
model_list:
  - model_name: "gpt-5.4"
    litellm_params:
      model: "openai/gpt-5.4"
      api_base: "os.environ/NEWAPI_OPENAI_A_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_A_KEY"

  - model_name: "gpt-5.4-backup"
    litellm_params:
      model: "openai/gpt-5.4"
      api_base: "os.environ/NEWAPI_OPENAI_B_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_B_KEY"

router_settings:
  fallbacks:
    - gpt-5.4:
        - gpt-5.4-backup
  num_retries: 2
  timeout: 60000
```

## 方案 E：渠道 / 别名路由

思路：

- 不同上游或不同策略用不同渠道名暴露
- 客户端主动选择渠道，而不是只传裸模型名

### 常见命名风格

- `stable/gpt-5.4`
- `backup/gpt-5.4`
- `lowcost/gpt-5.4`
- `google/gemini-3.1-pro`

### 优点

- 客户端可以显式表达偏好
- 对运维和排障很直观

### 缺点

- 需要给客户端额外说明命名规范
- 不是所有调用方都愿意修改模型名

### `litellm.local.yaml` 示例

```yaml
model_list:
  - model_name: "stable/gpt-5.4"
    litellm_params:
      model: "openai/gpt-5.4"
      api_base: "os.environ/NEWAPI_OPENAI_A_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_A_KEY"

  - model_name: "backup/gpt-5.4"
    litellm_params:
      model: "openai/gpt-5.4"
      api_base: "os.environ/NEWAPI_OPENAI_B_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_B_KEY"

  - model_name: "lowcost/gpt-5.4-mini"
    litellm_params:
      model: "openai/gpt-5.4-mini"
      api_base: "os.environ/NEWAPI_OPENAI_B_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_B_KEY"
```

## 方案 F：按 team / tenant 路由

思路：

- 不同团队、不同租户看到相同的对外模型名
- 但它们在 LiteLLM 内部实际命中不同上游 NewAPI

### 优点

- 多租户隔离能力强
- 客户端不一定需要感知上游差异

### 缺点

- 依赖 LiteLLM 自身的 key / team 体系
- 比纯静态配置更难排障

### `litellm.local.yaml` 示例

```yaml
model_list:
  - model_name: "gpt-5.4-tenant-a"
    model_info:
      team_id: "team-a"
      team_public_model_name: "gpt-5.4"
    litellm_params:
      model: "openai/gpt-5.4"
      api_base: "os.environ/NEWAPI_TENANT_A_API_BASE"
      api_key: "os.environ/NEWAPI_TENANT_A_KEY"

  - model_name: "gpt-5.4-tenant-b"
    model_info:
      team_id: "team-b"
      team_public_model_name: "gpt-5.4"
    litellm_params:
      model: "openai/gpt-5.4"
      api_base: "os.environ/NEWAPI_TENANT_B_API_BASE"
      api_key: "os.environ/NEWAPI_TENANT_B_KEY"
```

说明：

- 这个方案通常还需要配合 LiteLLM 的 team / virtual key 管理
- 不同 team 通过相同模型名访问时，LiteLLM 会返回不同的 team-specific deployment

## 方案 G：混合架构

这是真正的“多 NewAPI、多渠道”综合方案。

典型组合方式：

- 常用模型：方案 A
- 新模型透传：方案 C
- 同模型多上游容灾：方案 D
- 渠道化路由：方案 E
- 特定租户隔离：方案 F

### 一个常见混合结构

```yaml
model_list:
  # 稳定主模型
  - model_name: "gpt-5.4"
    litellm_params:
      model: "openai/gpt-5.4"
      api_base: "os.environ/NEWAPI_OPENAI_A_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_A_KEY"

  # 同模型备用
  - model_name: "gpt-5.4-backup"
    litellm_params:
      model: "openai/gpt-5.4"
      api_base: "os.environ/NEWAPI_OPENAI_B_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_B_KEY"

  # 渠道名
  - model_name: "lowcost/gpt-5.4-mini"
    litellm_params:
      model: "openai/gpt-5.4-mini"
      api_base: "os.environ/NEWAPI_OPENAI_B_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_B_KEY"

  # 列表外兜底
  - model_name: "*"
    litellm_params:
      model: "openai/*"
      api_base: "os.environ/NEWAPI_OPENAI_A_API_BASE"
      api_key: "os.environ/NEWAPI_OPENAI_A_KEY"

router_settings:
  fallbacks:
    - gpt-5.4:
        - gpt-5.4-backup
```

## 推荐演进顺序

如果你现在是单一 `NEWAPI_API_BASE` / `NEWAPI_KEY` 起步，建议按这个顺序升级：

1. 先做方案 A  
   先把多个 NewAPI 接进来，确保模型能稳定分流

2. 再做方案 C  
   保留常用模型清单，同时允许列表外模型透传

3. 再做方案 D  
   对关键模型补主备与容灾

4. 最后再考虑方案 E / F  
   渠道化和租户隔离都更依赖长期维护规范

## 当前仓库最适合的起步方案

结合当前 `ai/gateway/litellm` 目录里的配置形态，我会推荐：

- 起步：方案 A
- 过渡：方案 C
- 关键模型容灾：方案 D

也就是：

- 先按模型显式绑定多个 NewAPI
- 再保留一个末尾 `*` fallback
- 对关键模型再补单独的备用上游

这样最接近现在这套配置的演进方向，且不需要一开始就引入太重的 team / tenant 体系。

## 注意事项

- `/models` 返回的是 LiteLLM 当前注册的模型名，不是所有上游 NewAPI 的完整模型集合
- `*` fallback 只代表“可以透传”，不代表这些模型会自动出现在 `/models`
- 当多个 NewAPI 都提供同名模型时，建议尽早决定是否需要渠道前缀或显式主备命名
- 当前环境下 `claude-opus-4-6` 非流式请求存在兼容性限制，建议优先使用 `stream=true`
- 生产环境建议尽早把“显式主模型”和“临时透传模型”在文档中区分清楚，避免客户端误把 fallback 当成正式 SLA
