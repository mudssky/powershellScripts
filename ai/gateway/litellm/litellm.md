# LiteLLM 网关说明

这个目录用于启动一个基于 LiteLLM Proxy 的多上游网关，当前默认同时支持 NewAPI OpenAI 兼容模型、Claude Anthropic 原生模型与智谱 GLM Coding Plan。

相关文件职责如下：

- `litellm.local.yaml`：本地默认配置，定义 LiteLLM 的显式模型、GLM 专属路由与上游连接方式。
- `qwen.yaml`：历史示例配置，保留了固定模型与降级策略写法，可作为按模型显式映射时的参考。
- `compose.yaml`：LiteLLM 容器模板，定义镜像、端口、挂载和默认环境变量。
- `start.ps1`：统一入口，封装常用 `docker compose` 操作。
- `.env.example`：开发环境变量示例。
- `.env.production.example`：生产环境变量示例。
- `.env.local`：本地私有环境变量，保存 `NEWAPI_API_BASE`、`NEWAPI_KEY`、可选的 `NEWAPI_ANTHROPIC_API_BASE` / `NEWAPI_ANTHROPIC_KEY`、`Z_AI_CODING_API_BASE`、`Z_AI_API_KEY`、`LITELLM_MASTER_KEY`、可选 `DATABASE_URL`。

固定常量如 `PORT=4000`、`CONFIG_FILE_PATH=/app/config.yaml` 保留在 `compose.yaml` 内部；环境差异值建议集中在 `.env.local`，再通过 `start.ps1` 追加的 `--env-file` 和 `compose.yaml` 的 `environment` 白名单注入到容器。

## 环境变量

建议先在 `ai/gateway/litellm/.env.local` 中配置以下值：

```dotenv
LITELLM_IMAGE=docker.litellm.ai/berriai/litellm:main-latest
LITELLM_HOST_PORT=34000
NEWAPI_API_BASE=http://new-api.example.com/v1
NEWAPI_KEY=sk-newapi-dev-xxxx
# 可选：只有 Claude 需要单独上游时才覆盖；否则默认复用 NEWAPI_API_BASE / NEWAPI_KEY
# NEWAPI_ANTHROPIC_API_BASE=http://anthropic-api.example.com
# NEWAPI_ANTHROPIC_KEY=sk-anthropic-dev-xxxx
Z_AI_CODING_API_BASE=https://open.bigmodel.cn/api/coding/paas/v4
Z_AI_API_KEY=sk-zai-dev-xxxx
LITELLM_MASTER_KEY=sk-litellm-123456
DATABASE_URL=postgresql://postgres:12345678@host.docker.internal:5432/litellm
# LITELLM_ANTHROPIC_DISABLE_URL_SUFFIX=true
```

说明：

- `LITELLM_IMAGE`：LiteLLM 镜像，可用于生产环境固定到经过验证的标签。
- `LITELLM_HOST_PORT`：宿主机暴露端口，默认 `34000`。
- `NEWAPI_API_BASE`：NewAPI 的 OpenAI 兼容接口地址，建议带上 `/v1`。
- `NEWAPI_KEY`：LiteLLM 转发到 NewAPI 时使用的上游密钥。
- `NEWAPI_ANTHROPIC_API_BASE`：可选覆盖项；如果 Claude 需要走独立 Anthropic 兼容入口，可填写已被 Claude Code 验证可用的地址。不配置时，Claude 默认复用 `NEWAPI_API_BASE`。
- `NEWAPI_ANTHROPIC_KEY`：可选覆盖项；如果 Claude 需要独立上游密钥可单独提供。不配置时，Claude 默认复用 `NEWAPI_KEY`。
- `LITELLM_ANTHROPIC_DISABLE_URL_SUFFIX`：可选开关；如果 Claude 实际使用的 Anthropic 上游地址已经包含完整 API 路径，可设置为 `true` 禁止 LiteLLM 自动追加后缀。
- `Z_AI_CODING_API_BASE`：智谱 GLM Coding Plan 的 OpenAI 兼容接口地址，默认建议使用官方专属端点。
- `Z_AI_API_KEY`：LiteLLM 转发 `GLM-*` 请求到智谱 Coding Plan 时使用的上游密钥。
- `LITELLM_MASTER_KEY`：LiteLLM Proxy 对外暴露的网关密钥。
- `DATABASE_URL`：LiteLLM 的数据库连接串；如果未配置，会回退到默认的宿主机 PostgreSQL 地址。
- `DASHSCOPE_API_KEY` / `DASHSCOPE_API_BASE`：可选兼容项；只有切回 `qwen.yaml` 或其他百炼配置时才需要提供。

如果你想准备生产环境变量，可直接复制 `./.env.production.example` 再按实际环境改值。

## 启动方式

推荐直接使用 `start.ps1`：

```powershell
./ai/gateway/litellm/start.ps1
```

默认等价于：

```powershell
docker compose --env-file ai/gateway/litellm/.env.local `
  -f ai/gateway/litellm/compose.yaml `
  --project-directory ai/gateway/litellm `
  up -d
```

说明：

- 这里保留 `--env-file`，而不是把 `.env.local` 改成 `env_file` 主方案，是因为它同时负责 compose 插值，例如 `image`、`ports`、`environment` 中的 `${...}`。
- `compose.yaml` 里的 `environment` 继续采用白名单注入，这样 `.env.local` 中与 LiteLLM 无关的变量不会自动进入容器。

## 常用命令

```powershell
./ai/gateway/litellm/start.ps1
./ai/gateway/litellm/start.ps1 up
./ai/gateway/litellm/start.ps1 down
./ai/gateway/litellm/start.ps1 restart
./ai/gateway/litellm/start.ps1 logs --tail 100
./ai/gateway/litellm/start.ps1 ps
./ai/gateway/litellm/start.ps1 pull
```

这些命令分别对应：

- `up`：后台启动或重建 LiteLLM 容器。
- `down`：停止并移除当前 compose 管理的资源。
- `restart`：重启 LiteLLM 容器。
- `logs`：默认跟随 LiteLLM 日志，可透传额外参数如 `--tail 100`。
- `ps`：查看当前容器状态。
- `pull`：拉取最新镜像，不自动重启。

## 直接使用原生命令

如果你想直接执行 `docker compose`，建议保持和脚本一致的参数：

```powershell
docker compose --env-file ai/gateway/litellm/.env.local `
  -f ai/gateway/litellm/compose.yaml `
  --project-directory ai/gateway/litellm `
  logs -f litellm
```

这样可以确保 `DATABASE_URL` 默认值与 `.env.local` 中的变量覆盖行为一致。

## 访问方式

默认端口映射如下：

```text
http://127.0.0.1:34000
```

OpenAI 兼容接口示例：

```powershell
curl http://127.0.0.1:34000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer sk-litellm-123456" `
  -d "{\"model\":\"gemini-2.5-flash\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}"
```

如果你使用的是 OpenAI 兼容客户端，但想访问 Claude，请显式传 `compat/...` 别名，例如：

```powershell
curl http://127.0.0.1:34000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer sk-litellm-123456" `
  -d "{\"model\":\"compat/claude-opus-4-6\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}"
```

说明：

- 默认 `claude-opus-*` 设计给 Anthropic 兼容客户端优先使用。
- `compat/claude-opus-*` 只是在 LiteLLM 内表达“这是给 OpenAI 兼容客户端保留的 Claude 入口”，底层仍然走同一个 Anthropic 原生上游。

如果你想通过 LiteLLM 调用 GLM Coding Plan，可直接传官方模型名，例如：

```powershell
curl http://127.0.0.1:34000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer sk-litellm-123456" `
  -d "{\"model\":\"GLM-5.1\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}"
```

## 模型查询

如果你想查看 LiteLLM 当前暴露的路由名，可调用：

```powershell
curl "http://127.0.0.1:34000/models?return_wildcard_routes=true" `
  -H "x-litellm-api-key: sk-litellm-123456"
```

当前 `litellm.local.yaml` 默认显式注册了 `gpt-5.4`、`gemini-3.1-pro`、`claude-opus-4-6`、`claude-opus-4-7`、`compat/claude-opus-4-6`、`compat/claude-opus-4-7`、`GLM-5.1` 七个主模型，并在末尾保留 `GLM-*` 与 `*` 两条 fallback 路由。因此 `/models` 会返回显式模型加上两条通配兜底路由。默认会看到类似下面的结果：

```json
{
  "data": [
    {"id": "gpt-5.4", "object": "model"},
    {"id": "gemini-3.1-pro", "object": "model"},
    {"id": "claude-opus-4-6", "object": "model"},
    {"id": "claude-opus-4-7", "object": "model"},
    {"id": "compat/claude-opus-4-6", "object": "model"},
    {"id": "compat/claude-opus-4-7", "object": "model"},
    {"id": "GLM-5.1", "object": "model"},
    {"id": "GLM-*", "object": "model"},
    {"id": "*", "object": "model"}
  ],
  "object": "list"
}
```

如果你想获取 NewAPI 实际可用的模型名，请直接调用上游：

```powershell
curl "$env:NEWAPI_API_BASE/models" `
  -H "Authorization: Bearer $env:NEWAPI_KEY"
```

如果你想获取智谱 Coding Plan 实际可用的模型名，请直接调用对应上游：

```powershell
curl "$env:Z_AI_CODING_API_BASE/models" `
  -H "Authorization: Bearer $env:Z_AI_API_KEY"
```

说明：

- 不要在当前配置下使用 `only_model_access_groups=true`，因为默认没有配置 model access groups，请求结果会是空数组。
- 如果客户端直接传 `model=qwen-plus` 之类的名称，前提是该名称必须真实存在于 NewAPI 的 `/models` 返回结果中。
- 如果客户端使用 OpenAI 兼容接口访问 Claude，建议显式传 `compat/claude-opus-*`，不要再把默认 `claude-opus-*` 当作 OpenAI 上游模型名理解。
- 如果客户端直接传 `model=GLM-4.7` 之类的官方名称，前提是该名称必须真实存在于智谱 Coding Plan 的 `/models` 返回结果中。
- 显式注册之外的 GLM 模型不会自动展开进 LiteLLM 的 `/models` 列表；它们会优先通过 `GLM-*` fallback 转发到智谱上游。
- 其它显式注册之外的非 GLM 模型，仍然通过最后的 `*` fallback 透传到 NewAPI。

## 配置说明

当前 `litellm.local.yaml` 的关键点：

- `model_list`：显式注册 `gpt-5.4`、`gemini-3.1-pro`、两条默认 Claude 原生模型、两条 Claude 兼容别名、`GLM-5.1`，并追加 `GLM-*` 与 `*` 两层兜底。
- 显式模型优先：常用模型可以稳定出现在 `/models` 里，也方便客户端按固定名称接入。
- `claude-opus-*`：默认映射到 LiteLLM 的 Anthropic provider，优先服务 Anthropic 兼容客户端。
- `compat/claude-opus-*`：为 OpenAI 兼容客户端保留显式 Claude 别名，但底层仍然走同一个 Anthropic 原生上游。
- `GLM-*` fallback：对智谱 Coding Plan 已存在但未显式注册的 GLM 官方模型保留透传能力，同时避免误落到 NewAPI。
- `*` fallback：对 NewAPI 已存在但未显式注册的非 GLM 模型保留透传能力，减少频繁改本地配置的成本。
- `litellm_params.model`：OpenAI / Gemini / GLM 继续映射到 `openai/<模型名>`；Claude 显式模型与兼容别名映射到 `anthropic/<模型名>`。
- `master_key`：开启 LiteLLM 网关鉴权，避免任何能访问端口的客户端都直接调用上游。
- `Codex` 直连：当前 `ai/coding/codex/config.toml` 里的 `z.ai` provider 保持不变；本目录改动只补充 LiteLLM 网关入口。
