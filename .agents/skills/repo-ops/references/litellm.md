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

## 配置速查

### Provider 参数模式

- NewAPI OpenAI 兼容模型：使用 `api_base: os.environ/NEWAPI_API_BASE`、`api_key: os.environ/NEWAPI_KEY`、`model: openai/<上游模型名>`。常见入口包括 `gpt-5.5`、`gemini-3.1-pro` 与最后的 `*` 透传兜底。
- NewAPI Anthropic / Claude 模型：使用 `api_base: os.environ/NEWAPI_ANTHROPIC_API_BASE`、`api_key: os.environ/NEWAPI_ANTHROPIC_KEY`、`model: anthropic/<上游模型名>`。不要把默认 Claude 原生上游写成 `openai/<claude>`。
- 智谱 Coding Plan OpenAI 链路：使用 `Z_AI_CODING_API_BASE` / `Z_AI_API_KEY`，模型写 `openai/GLM-5.1` 或 `openai/GLM-*`。`claw-plan` 与 `claw-glmplan-5.1` 都走这条链路。
- 智谱 Claude Code Anthropic 链路：使用 `Z_AI_ANTHROPIC_API_BASE` / `Z_AI_API_KEY`，模型写 `anthropic/GLM-5.1`，只服务 `cc-glmplan-*`。
- DeepSeek OpenAI 兜底：使用 `DEEPSEEK_OPENAI_API_BASE` / `DEEPSEEK_API_KEY`，模型写 `openai/deepseek-v4-flash`，当前只给 `claw-glmplan-5.1` 兜底。
- DeepSeek Anthropic 兜底：使用 `DEEPSEEK_ANTHROPIC_API_BASE` / `DEEPSEEK_API_KEY`，模型写 `anthropic/deepseek-v4-pro[1m]` 或 `anthropic/deepseek-v4-flash`，只给 Claude Code 路由兜底。
- 小米 Mimo 直连：使用 `MIMO_API_BASE` / `MIMO_API_KEY`，模型写 `openai/mimo-v2.5-pro` 或 `openai/mimo-v2.5`，不经过 NewAPI。

### 视觉能力声明

- 只有真实可接收图片输入的模型才在 `model_info` 里写 `supports_vision: true`。
- `claw-plan` 可以声明 `supports_vision: true`，但这表示对外入口支持图片请求；底层 GLM 不支持视觉，图片请求必须由 callback 在 Router 选部署前改写。
- `mimo-v2.5` 是当前 claw 视觉目标，必须声明 `supports_vision: true`。
- `mimo-v2.5-pro` 是文本兜底模型，不声明视觉能力；如果图片请求落到它并返回 `No endpoints found that support image input`，说明视觉目标配错了。
- NewAPI 侧显式视觉模型也要声明 `supports_vision: true`，这样 `/model/info` 与客户端能力筛选才可靠。

### 固定参数

- `claw-deepseek-v4-flash` 固定 `reasoning_effort: "max"`，用于 OpenAI 兼容 agent 兜底时开启最大思考。
- `claude-code-deepseek-*` 不配置 `additional_drop_params` 丢弃 `thinking` / `reasoning_effort` / `output_config` / `output_config.effort`；历史 thinking 块兼容由 callback sanitizer 处理。
- GLM Claude Code 主入口保留 `cooldown_time: 3600`；真实 5 小时额度窗口由 `GlmCooldownAdapter` 解析上游 reset 时间后做长冷却。
- `drop_params: true` 与 `modify_params: true` 属于全局兼容设置，修改前先确认不会破坏 Claude Code Anthropic messages 兜底。

### Fallback 写法

`router_settings.fallbacks` 使用 model group 到 model group 的映射，不写 provider 模型名：

```yaml
router_settings:
  fallbacks:
    - cc-glmplan-opus:
        - claude-code-deepseek-v4-pro
    - cc-glmplan-haiku:
        - claude-code-deepseek-v4-flash
    - claw-plan:
        - mimo-v2.5-pro
    - claw-glmplan-5.1:
        - claw-deepseek-v4-flash
```

- `claw-plan -> mimo-v2.5-pro` 只处理文本 GLM 失败后的兜底，不处理图片模态选择。
- `claw-plan` 图片请求由 `ClawVisionRouterAdapter` 在 `async_pre_call_hook` 阶段改写为 `mimo-v2.5`，不要期待先撞 GLM 再 fallback。
- `cc-glmplan-*` fallback 只指向 `claude-code-deepseek-*`，保持 Anthropic messages 语义。
- `claw-*` OpenAI 兼容 fallback 不指向 `claude-code-deepseek-*`，避免 OpenAI Chat 请求继承 Claude Code sanitizer 假设。

### 修改同步清单

- 改模型、provider、fallback、视觉能力：同步 `litellm.local.yaml` 与 `newapi.yaml`。
- 新增环境变量：同步 `compose.yaml`、`.env.example`、`.env.production.example` 与本文档的变量列表。
- 新增或调整 callback：同步 `callbacks/framework/hub.py` 注册表、`callbacks/tests/` 回归测试与 `compose.yaml` 挂载边界。
- 改 `claw-` OpenAI 兼容链路：检查 `ClawVisionRouterAdapter`、`GlmCooldownAdapter`、`router_settings.fallbacks` 与 `.trellis/spec/infra/litellm-gateway.md`。
- 改 Claude Code Anthropic fallback：检查 DeepSeek thinking sanitizer、GLM cooldown、`cc-glmplan-*` fallback 与 Claude Code 文档。

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

配置和运行态建议按风险逐层验证：

```bash
ruby -ryaml -e "ARGV.each { |p| YAML.load_file(p) }; puts 'YAML parse OK'" ai/gateway/litellm/litellm.local.yaml ai/gateway/litellm/newapi.yaml
python ai/gateway/litellm/callbacks/tests/test_claw_vision_router.py
python ai/gateway/litellm/callbacks/tests/test_gateway_callback.py
python ai/gateway/litellm/callbacks/tests/test_glm_cooldown_adapter.py
pnpm qa
```

修改配置、callback 挂载或 compose 环境后应用运行态：

```powershell
./ai/gateway/litellm/start.ps1 apply
```

真实请求依赖 Docker、上游密钥、额度和网络；本地 YAML 解析通过不等价于上游可用。视觉 smoke test 优先用 base64 data URL，小米 `mimo-v2.5` 对部分公开远程图片 URL 可能返回 `Param Incorrect`。
