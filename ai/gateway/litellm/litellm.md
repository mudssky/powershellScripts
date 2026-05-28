# LiteLLM 网关说明

这个目录用于启动一个基于 LiteLLM Proxy 的多上游网关，当前默认同时支持 NewAPI OpenAI 兼容模型、Claude Anthropic 原生模型、智谱 GLM Coding Plan，以及 Claude Code 的 GLM 优先 / DeepSeek 兜底入口。

相关文件职责如下：

- `litellm.local.yaml`：本地默认配置，定义 LiteLLM 的显式模型、GLM 专属路由、Claude Code 降级路由与上游连接方式。
- `qwen.yaml`：历史示例配置，保留了固定模型与降级策略写法，可作为按模型显式映射时的参考。
- `compose.yaml`：LiteLLM 容器模板，定义镜像、端口、挂载和默认环境变量。
- `start.ps1`：统一入口，封装常用 `docker compose` 操作。
- `.env.example`：开发环境变量示例。
- `.env.production.example`：生产环境变量示例。
- `.env.local`：本地私有环境变量，保存 `NEWAPI_API_BASE`、`NEWAPI_KEY`、可选的 `NEWAPI_ANTHROPIC_API_BASE` / `NEWAPI_ANTHROPIC_KEY`、`Z_AI_CODING_API_BASE`、`Z_AI_ANTHROPIC_API_BASE`、`Z_AI_API_KEY`、`DEEPSEEK_ANTHROPIC_API_BASE`、`DEEPSEEK_OPENAI_API_BASE`、`DEEPSEEK_API_KEY`、`MIMO_API_BASE`、`MIMO_API_KEY`、`LITELLM_MASTER_KEY`、可选 `DATABASE_URL`。

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
Z_AI_ANTHROPIC_API_BASE=https://open.bigmodel.cn/api/anthropic
Z_AI_API_KEY=sk-zai-dev-xxxx
DEEPSEEK_ANTHROPIC_API_BASE=https://api.deepseek.com/anthropic
DEEPSEEK_OPENAI_API_BASE=https://api.deepseek.com/v1
DEEPSEEK_API_KEY=sk-deepseek-dev-xxxx
MIMO_API_BASE=https://token-plan-cn.xiaomimimo.com/v1
MIMO_API_KEY=sk-mimo-dev-xxxx
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
- `Z_AI_ANTHROPIC_API_BASE`：智谱 GLM Coding Plan 的 Anthropic 兼容接口地址，Claude Code GLM 优先入口会使用它。
- `Z_AI_API_KEY`：LiteLLM 转发 `GLM-*` 请求到智谱 Coding Plan 时使用的上游密钥。
- `DEEPSEEK_ANTHROPIC_API_BASE`：DeepSeek 的 Anthropic 兼容接口地址，默认用于 Claude Code 的兜底路由。
- `DEEPSEEK_OPENAI_API_BASE`：DeepSeek 的 OpenAI 兼容接口地址，默认用于 `claw-` agent 兜底路由。
- `DEEPSEEK_API_KEY`：LiteLLM 转发 DeepSeek 兜底请求时使用的上游密钥。
- `MIMO_API_BASE`：小米 Mimo 的 OpenAI 兼容接口地址，建议带上 `/v1`；`claw-plan` 的视觉请求与 GLM 兜底会直连这里。
- `MIMO_API_KEY`：LiteLLM 转发到小米 Mimo 时使用的上游密钥。
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
./ai/gateway/litellm/start.ps1 apply
./ai/gateway/litellm/start.ps1 down
./ai/gateway/litellm/start.ps1 restart
./ai/gateway/litellm/start.ps1 logs --tail 100
./ai/gateway/litellm/start.ps1 ps
./ai/gateway/litellm/start.ps1 pull
```

这些命令分别对应：

- `up`：后台启动或重建 LiteLLM 容器。
- `apply`：强制重建 LiteLLM 服务，适合修改 `litellm.local.yaml` 后让新配置重新加载。
- `down`：停止并移除当前 compose 管理的资源。
- `restart`：重启 LiteLLM 容器。
- `logs`：默认跟随 LiteLLM 日志，可透传额外参数如 `--tail 100`。
- `ps`：查看当前容器状态。
- `pull`：拉取最新镜像，不自动重启。

## Coding Plan 窗口预热

通用窗口预热工具位于 `ai/coding/window-warmer/`。它是独立宿主机脚本，不属于 LiteLLM callback 或 Compose 服务；默认配置通过 LiteLLM Python SDK 直连智谱 Coding Plan 上游端点，避免经过本机 LiteLLM Proxy 的 fallback 路由。

启动默认配置：

```bash
pm2 start ai/coding/window-warmer/window-warmer.pm2.config.cjs
```

常用管理：

```bash
pm2 logs coding-window-warmer
pm2 restart coding-window-warmer
pm2 stop coding-window-warmer
pm2 save
```

如果只想直接试跑脚本：

```bash
cd ai/coding/window-warmer
uv run python window_warmer.py --config window-warmer.toml --print-next
```

多 Coding Plan、`fixed_times` / `interval` 调度模式和测试命令见 [README](../../coding/window-warmer/README.md)。

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

## OpenAI 兼容 agent 的 claw 入口

Hermes 等 OpenAI 兼容 agent 后续可以把模型固定为 `claw-plan`，由 LiteLLM 先走智谱 `GLM-5.1` OpenAI 兼容端点；如果 GLM 额度耗尽或临时不可用，网关会 fallback 到直连小米 `mimo-v2.5-pro`。带图片的请求会在 Router 选择部署前切到直连小米 `mimo-v2.5`，避免误打不支持视觉的 GLM：

```powershell
curl http://127.0.0.1:34000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer sk-litellm-123456" `
  -d "{\"model\":\"claw-plan\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}"
```

说明：

- `claw-plan` 是推荐给 agent 配置使用的稳定入口；当前底层为 `GLM-5.1`，未来升级底层模型时可尽量不改客户端配置。
- `claw-glmplan-5.1` 是显式版本入口，适合调试或需要固定 GLM 版本的调用。
- `mimo-v2.5-pro` 是 `claw-plan` 的文本 fallback，直连小米 OpenAI 兼容端点，不经过 NewAPI。
- `mimo-v2.5` 是 `claw-plan` 的视觉入口，显式声明 `supports_vision: true`；`mimo-v2.5-pro` 不支持视觉，不应声明视觉能力。
- `claw-deepseek-v4-flash` 是 `claw-glmplan-5.1` 的 DeepSeek OpenAI 兼容 fallback 入口，底层模型为 `deepseek-v4-flash`，并默认传递 `reasoning_effort: "max"` 开启最大思考模式。
- `claw-` 路由使用 OpenAI provider；Mimo 路由使用 `MIMO_API_BASE`，DeepSeek fallback 使用 `DEEPSEEK_OPENAI_API_BASE`，不会复用 Claude Code 的 Anthropic messages 兜底路由，也不会进入 DeepSeek thinking sanitizer 的语义边界。
- 本仓库当前尚未创建 Hermes 配置文件，因此这里只记录网关入口；创建 Hermes 配置时把 Base URL 指向 `http://127.0.0.1:34000/v1`，API Key 使用 `LITELLM_MASTER_KEY`，模型名使用 `claw-plan`。

## Claude Code 的 GLM 优先入口

如果你想让 Claude Code 优先使用 GLM-5.1，并在 Coding Plan 额度耗尽后自动切到 DeepSeek，可以把 Claude Code 指向 LiteLLM 的 Anthropic 兼容入口：

```json
{
  "env": {
    "ANTHROPIC_API_KEY": "sk-litellm-123456",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:34000",
    "ANTHROPIC_MODEL": "cc-glmplan-opus",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "cc-glmplan-opus",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "cc-glmplan-opus",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "cc-glmplan-haiku",
    "CLAUDE_CODE_SUBAGENT_MODEL": "cc-glmplan-haiku",
    "CLAUDE_CODE_EFFORT_LEVEL": "max"
  },
  "model": "cc-glmplan-opus"
}
```

说明：

- 这段配置应放在 `ai/coding/claude/config/settings.local.json`，再运行 `pwsh -NoProfile -File ./ai/coding/claude/Sync-ClaudeConfig.ps1` 生成最终配置。
- `ANTHROPIC_API_KEY` 使用 LiteLLM 的 `LITELLM_MASTER_KEY`，不要填写上游真实密钥。
- `cc-glmplan-opus` 先走智谱 `GLM-5.1`；遇到 429 / `RateLimitError` 时由 LiteLLM 网关短重试，仍失败后会降级到 `claude-code-deepseek-v4-pro`。
- `cc-glmplan-haiku` 先走智谱 `GLM-5.1`；遇到 429 / `RateLimitError` 时由 LiteLLM 网关短重试，仍失败后会降级到 `claude-code-deepseek-v4-flash`。
- DeepSeek 兜底路由会保留当前请求的 `thinking` / `reasoning_effort` / `output_config.effort`，让 DeepSeek Anthropic 兼容接口继续承接 Claude Code thinking / effort；Claude `/v1/messages` 原生路径会通过 callback hub 中的 DeepSeek sanitizer adapter 在发往 DeepSeek 前递归清理无签名/不完整的历史 `content[].thinking` / `redacted_thinking` / `thinking_blocks`，同时保留带 `signature` 或 `data` 的上游不透明 thinking 块。
- sanitizer 会输出不含正文的结构诊断日志，事件名为 `deepseek thinking sanitized`；排查 fallback 时重点看 `stage`、`top_level_thinking_before/after`、`removed_thinking_paths`、`remaining_thinking_paths` 与 `preserved_thinking_blocks_after`，其中 `remaining_thinking_paths: []` 表示发往 DeepSeek 前已没有不兼容 thinking 历史路径。
- DeepSeek 官方 Claude Code 直连配置推荐 `CLAUDE_CODE_EFFORT_LEVEL=max`；在 DeepSeek Anthropic 兼容接口里，effort 对应 `output_config.effort`。跨供应商 fallback 只清理历史 assistant thinking 块，不把当前请求的 top-level `thinking` 改成 disabled，也不在路由配置里丢弃 thinking / effort。
- GLM 两个 Claude Code 入口的 `cooldown_time=3600` 只作为 LiteLLM 内建短冷却；GLM 429 返回 reset 时间后，callback hub 中的 GLM cooldown adapter 会记录 `reset + 60 秒`，在冷却期间把后续 `cc-glmplan-*` 请求预先切到对应 DeepSeek 兜底，避免 5 小时窗口内每小时重复探测。
- 429 无感只覆盖这两个 Claude Code GLM 入口；如果 GLM 重试和 DeepSeek fallback 全部失败，LiteLLM 仍会把最终错误返回给 Claude Code / 客户端。

## 模型查询

如果你想查看 LiteLLM 当前暴露的路由名，可调用：

```powershell
curl "http://127.0.0.1:34000/models?return_wildcard_routes=true" `
  -H "x-litellm-api-key: sk-litellm-123456"
```

当前 `litellm.local.yaml` 默认显式注册了 `gpt-5.5`、`gemini-3.1-pro`、`claude-opus-4-6`、`claude-opus-4-7`、`compat/claude-opus-4-6`、`compat/claude-opus-4-7`、四条 Claude Code 专用模型、三条 `claw-` OpenAI 兼容 agent 模型、两条 Mimo 直连模型、`GLM-5.1` 与 `gpt*spark` 等主模型，并在末尾保留 `GLM-*` 与 `*` 两条 fallback 路由。因此 `/models` 会返回显式模型加上两条通配兜底路由。默认会看到类似下面的结果：

```json
{
  "data": [
    {"id": "gpt-5.5", "object": "model"},
    {"id": "gemini-3.1-pro", "object": "model"},
    {"id": "claude-opus-4-6", "object": "model"},
    {"id": "claude-opus-4-7", "object": "model"},
    {"id": "compat/claude-opus-4-6", "object": "model"},
    {"id": "compat/claude-opus-4-7", "object": "model"},
    {"id": "cc-glmplan-opus", "object": "model"},
    {"id": "cc-glmplan-haiku", "object": "model"},
    {"id": "claude-code-deepseek-v4-pro", "object": "model"},
    {"id": "claude-code-deepseek-v4-flash", "object": "model"},
    {"id": "GLM-5.1", "object": "model"},
    {"id": "GLM-*", "object": "model"},
    {"id": "claw-plan", "object": "model"},
    {"id": "claw-glmplan-5.1", "object": "model"},
    {"id": "mimo-v2.5-pro", "object": "model"},
    {"id": "mimo-v2.5", "object": "model"},
    {"id": "claw-deepseek-v4-flash", "object": "model"},
    {"id": "gpt*spark", "object": "model"},
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
- 如果客户端是 Hermes 等 OpenAI 兼容 agent，建议显式传 `claw-plan`，由网关统一处理文本 GLM 优先、文本 Mimo Pro 兜底和图片 Mimo 2.5 路由。
- 如果客户端直接传 `model=GLM-4.7` 之类的官方名称，前提是该名称必须真实存在于智谱 Coding Plan 的 `/models` 返回结果中。
- 显式注册之外的 GLM 模型不会自动展开进 LiteLLM 的 `/models` 列表；它们会优先通过 `GLM-*` fallback 转发到智谱上游。
- 其它显式注册之外的非 GLM 模型，仍然通过最后的 `*` fallback 透传到 NewAPI。

## 配置说明

当前 `litellm.local.yaml` 的关键点：

- `model_list`：显式注册 `gpt-5.5`、`gemini-3.1-pro`、两条默认 Claude 原生模型、两条 Claude 兼容别名、四条 Claude Code 专用模型、三条 `claw-` OpenAI 兼容 agent 模型、`GLM-5.1` 与 `gpt*spark`，并追加 `GLM-*` 与 `*` 两层兜底。
- 显式模型优先：常用模型可以稳定出现在 `/models` 里，也方便客户端按固定名称接入。
- `claude-opus-*`：默认映射到 LiteLLM 的 Anthropic provider，优先服务 Anthropic 兼容客户端。
- `compat/claude-opus-*`：为 OpenAI 兼容客户端保留显式 Claude 别名，但底层仍然走同一个 Anthropic 原生上游。
- `cc-glmplan-opus`：为 Claude Code 提供稳定主入口，优先走智谱 `GLM-5.1` 的 Anthropic 兼容端点。
- `cc-glmplan-haiku`：为 Claude Code Haiku / subagent 流量提供独立入口，优先走智谱 `GLM-5.1` 的 Anthropic 兼容端点。
- `claude-code-deepseek-v4-pro` / `claude-code-deepseek-v4-flash`：作为 GLM 额度耗尽或临时不可用时的 DeepSeek 兜底路由。
- `claude-code-deepseek-*` 参数策略：这是 Claude Code Anthropic messages 专用兜底入口，不配置 `additional_drop_params` 丢弃 `thinking` / `reasoning_effort`；如需 Chat/Responses 保守兼容，应新增独立 safe 路由。
- `claw-plan`：为 OpenAI 兼容 agent 提供稳定默认入口；纯文本优先走智谱 `GLM-5.1` OpenAI 兼容端点，图片请求由 callback 提前切到直连小米 `mimo-v2.5`。
- `claw-glmplan-5.1`：为 OpenAI 兼容 agent 提供显式 GLM 版本入口，便于调试和固定版本调用。
- `mimo-v2.5-pro`：作为 `claw-plan` 的文本 GLM 兜底，直连小米 OpenAI 兼容端点，不经过 NewAPI；该模型不声明视觉能力。
- `mimo-v2.5`：作为 `claw-plan` 的视觉入口，直连小米 OpenAI 兼容端点，不经过 NewAPI，并声明 `supports_vision: true`。
- `claw-deepseek-v4-flash`：作为 `claw-glmplan-5.1` 的 DeepSeek OpenAI 兼容兜底，底层模型为 `deepseek-v4-flash`，默认 `reasoning_effort=max`。
- `callbacks/gateway_callback.py`：LiteLLM 统一 callback hub。配置层只挂载这个入口，hub 再把生命周期 hook 分发给启用的 adapter。
- `callbacks/framework/`：LiteLLM callback framework 基础设施，包含 hub 与 adapter 抽象。顶层 `callbacks/gateway_callback.py` 只作为 LiteLLM 配置可 import 的薄入口。
- `callbacks/adapters/deepseek/thinking_sanitizer.py`：只在 DeepSeek Anthropic 请求发出前清理无签名/不完整的历史 `thinking` / `redacted_thinking` / `thinking_blocks` content 块；带 `signature` 的 thinking 和带 `data` 的 redacted thinking 必须保留回传。这是给 Claude Code `/v1/messages` pass-through 路径补的兼容层，不能只靠普通参数丢弃替代。该 adapter 必须原地修改 `messages` 列表引用，因为 Anthropic pass-through handler 会继续使用函数位置参数里的原 messages 对象。
- `callbacks/adapters/glm/cooldown.py`：在失败事件中解析 GLM 429 中文 reset 时间，按 `reset + LITELLM_GLM_RESET_BUFFER_SECONDS` 记录冷却截止时间；后续请求进入 Router 前，如果模型仍在冷却期，就把 `cc-glmplan-opus` 改写为 `claude-code-deepseek-v4-pro`，把 `cc-glmplan-haiku` 改写为 `claude-code-deepseek-v4-flash`。解析失败但确认是额度/限流错误时使用 `LITELLM_GLM_FALLBACK_COOLDOWN_SECONDS` 兜底；普通上游错误不会触发长冷却。
- DeepSeek effort 兼容：不要把 `thinking`、`reasoning_effort`、`output_config` 或 `output_config.effort` 加入 DeepSeek Claude Code 兜底路由的丢弃参数；DeepSeek Anthropic 兼容接口使用这些字段承接 Claude Code thinking / effort。
- DeepSeek OpenAI 兼容兜底：`claw-deepseek-v4-flash` 使用 `DEEPSEEK_OPENAI_API_BASE` 和 OpenAI provider，通过 `reasoning_effort=max` 启用最大思考模式，不复用 Claude Code Anthropic messages sanitizer。
- `litellm_settings.callbacks`：加载 `callbacks.gateway_callback.proxy_handler_instance`；`compose.yaml` 必须挂载 `./callbacks:/app/callbacks:ro`，修改后需要重建容器才能让新挂载生效。
- `litellm_settings.modify_params`：允许 LiteLLM 对 Anthropic tool/thinking 消息做兼容修正；但它不能替代上面的 sanitizer，因为 DeepSeek 报错来自原生 `messages[].content[]` 历史块校验。
- `router_settings.num_retries` / `retry_policy.RateLimitErrorRetries`：让 Claude Code GLM 入口的瞬时 429 先在网关内短重试，避免直接把限流错误透给客户端。
- `router_settings.fallbacks`：把 Claude Code 的 GLM 主入口分别降级到对应 DeepSeek Anthropic 路由；`claw-plan` 降级到直连小米 `mimo-v2.5-pro`，`claw-glmplan-5.1` 降级到 `claw-deepseek-v4-flash`。LiteLLM 内建 1 小时 cooldown 只处理短期失败；GLM 5 小时额度窗口由 `GlmCooldownAdapter` 按上游 reset 时间做请求前避让。
- `GLM-*` fallback：对智谱 Coding Plan 已存在但未显式注册的 GLM 官方模型保留透传能力，同时避免误落到 NewAPI。
- `*` fallback：对 NewAPI 已存在但未显式注册的非 GLM 模型保留透传能力，减少频繁改本地配置的成本。
- `litellm_params.model`：OpenAI / Gemini / GLM OpenAI 兼容路由映射到 `openai/<模型名>`；Claude 显式模型、兼容别名与 Claude Code 专用模型映射到 `anthropic/<模型名>`。
- `master_key`：开启 LiteLLM 网关鉴权，避免任何能访问端口的客户端都直接调用上游。
- `Codex` 直连：当前 `ai/coding/codex/config.toml` 里的 `z.ai` provider 保持不变；本目录改动只补充 LiteLLM 网关入口。
