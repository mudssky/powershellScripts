# LiteLLM 网关运维

## 关键路径

- 目录：`ai/gateway/litellm/`
- 说明文档：`ai/gateway/litellm/litellm.md`
- 启动脚本：`ai/gateway/litellm/start.ps1`
- Compose 模板：`ai/gateway/litellm/compose.yaml`
- 本地配置：`ai/gateway/litellm/litellm.local.yaml`
- 同步配置：`ai/gateway/litellm/newapi.yaml`
- 环境示例：`.env.example`、`.env.production.example`
- 私有环境：`.env.local`，只读取变量名和存在性，不输出真实值。

## 常用命令

优先从仓库根目录执行：

```powershell
./ai/gateway/litellm/start.ps1
./ai/gateway/litellm/start.ps1 up
./ai/gateway/litellm/start.ps1 apply
./ai/gateway/litellm/start.ps1 restart
./ai/gateway/litellm/start.ps1 logs --tail 100
./ai/gateway/litellm/start.ps1 ps
./ai/gateway/litellm/start.ps1 pull
./ai/gateway/litellm/start.ps1 sync-models
```

- `up`：后台启动或重建 LiteLLM 容器。
- `apply`：修改 `litellm.local.yaml`、callback 挂载或 compose 环境后使用，强制重建 `litellm` 服务。
- `restart`：仅重启服务，适合不需要重建挂载和配置的场景。
- `logs --tail 100`：查看最近日志。
- `sync-models`：用 `litellm.local.yaml` 同步数据库模型列表。

## 配置约定

- `litellm.local.yaml` 是本地默认配置，`newapi.yaml` 需要跟随维护可复用模板。
- `compose.yaml` 通过环境变量白名单注入容器，不把 `.env.local` 全量暴露给服务。
- 修改模型路由、fallback 或 provider 参数时，检查 `.trellis/spec/infra/litellm-gateway.md`。
- 修改 `claw-` OpenAI 兼容 agent 路由时，同步检查 `litellm.local.yaml`、`newapi.yaml`、`.env.example`、`.env.production.example` 和文档。
- 修改 Claude Code Anthropic messages 兜底时，同步检查 `callbacks/`、`compose.yaml` 挂载、fallback、sanitizer 与 cooldown adapter。

## 模型入口

- `claw-plan`：OpenAI 兼容 agent 推荐稳定入口，文本优先走智谱 `GLM-5.1`，文本兜底到直连小米 `mimo-v2.5-pro`，图片请求由 callback 切到直连小米 `mimo-v2.5`。
- `mimo-v2.5-pro`：直连小米文本兜底模型，不声明视觉能力。
- `mimo-v2.5`：直连小米视觉模型，声明 `supports_vision: true`。
- `claw-glmplan-5.1`：显式 GLM 版本入口。
- `claw-deepseek-v4-flash`：`claw-` 的 DeepSeek OpenAI 兼容兜底，默认 `reasoning_effort=max`。
- `cc-glmplan-opus` / `cc-glmplan-haiku`：Claude Code GLM 优先入口。
- `claude-code-deepseek-v4-pro` / `claude-code-deepseek-v4-flash`：Claude Code Anthropic messages 兜底入口。

不要把 `claw-` OpenAI 兼容路由 fallback 到 `claude-code-deepseek-*`，也不要让 Claude Code 专用兜底复用 `DEEPSEEK_OPENAI_API_BASE`。

## 环境变量边界

常见变量名：

- `LITELLM_IMAGE`
- `LITELLM_HOST_PORT`
- `NEWAPI_API_BASE`
- `NEWAPI_KEY`
- `NEWAPI_ANTHROPIC_API_BASE`
- `NEWAPI_ANTHROPIC_KEY`
- `Z_AI_CODING_API_BASE`
- `Z_AI_ANTHROPIC_API_BASE`
- `Z_AI_API_KEY`
- `DEEPSEEK_ANTHROPIC_API_BASE`
- `DEEPSEEK_OPENAI_API_BASE`
- `DEEPSEEK_API_KEY`
- `MIMO_API_BASE`
- `MIMO_API_KEY`
- `LITELLM_MASTER_KEY`
- `DATABASE_URL`

排查时可以确认变量是否存在、是否注入容器、是否使用正确端点类型，但不要输出真实 key、token 或完整数据库连接串。

## 轻量验证

检查服务状态：

```powershell
./ai/gateway/litellm/start.ps1 ps
```

查看模型：

```powershell
curl "http://127.0.0.1:34000/models?return_wildcard_routes=true" `
  -H "x-litellm-api-key: <LITELLM_MASTER_KEY>"
```

OpenAI 兼容 smoke test：

```powershell
curl http://127.0.0.1:34000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" `
  -d "{\"model\":\"claw-plan\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}"
```

真实请求依赖 Docker、上游密钥、额度和网络；本地 YAML 解析通过不等价于上游可用。
