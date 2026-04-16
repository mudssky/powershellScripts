# LiteLLM 网关说明

这个目录用于启动一个基于 LiteLLM Proxy 的生产级 Qwen 网关，默认直连阿里百炼的 OpenAI 兼容接口。

相关文件职责如下：

- `qwen.yaml`：LiteLLM 生产配置，定义主模型、降级模型、限流、重试和超时策略。
- `compose.yaml`：LiteLLM 容器模板，定义镜像、端口、挂载和默认环境变量。
- `start.ps1`：统一入口，封装常用 `docker compose` 操作。
- `.env.example`：开发环境变量示例。
- `.env.production.example`：生产环境变量示例。
- `.env.local`：本地私有环境变量，保存 `DASHSCOPE_API_KEY`、`DASHSCOPE_API_BASE`、`LITELLM_MASTER_KEY`、可选 `DATABASE_URL`。

## 环境变量

建议先在 `ai/gateway/litellm/.env.local` 中配置以下值：

```dotenv
LITELLM_IMAGE=docker.litellm.ai/berriai/litellm:main-latest
LITELLM_HOST_PORT=34000
DASHSCOPE_API_KEY=sk-xxxx
DASHSCOPE_API_BASE=https://dashscope.aliyuncs.com/compatible-mode/v1
LITELLM_MASTER_KEY=sk-litellm-123456
DATABASE_URL=postgresql://postgres:12345678@host.docker.internal:5432/litellm
```

说明：

- `LITELLM_IMAGE`：LiteLLM 镜像，可用于生产环境固定到经过验证的标签。
- `LITELLM_HOST_PORT`：宿主机暴露端口，默认 `34000`。
- `DASHSCOPE_API_KEY`：阿里百炼 API Key。
- `DASHSCOPE_API_BASE`：阿里百炼 OpenAI 兼容接口地址；中国内地默认可用 `https://dashscope.aliyuncs.com/compatible-mode/v1`。
- `LITELLM_MASTER_KEY`：LiteLLM Proxy 对外暴露的网关密钥。
- `DATABASE_URL`：LiteLLM 的数据库连接串；如果未配置，会回退到默认的宿主机 PostgreSQL 地址。

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
  -d "{\"model\":\"qwen-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}"
```

## 配置说明

当前 `qwen.yaml` 的关键点：

- `qwen-chat`：主模型，默认走百炼 `qwen-plus`。
- `qwen-chat-fallback`：降级模型，默认走百炼 `qwen-flash`。
- `rpm`：在部署层做第一道限流保护，避免上游配额被瞬时打爆。
- `num_retries` + `timeout`：对临时失败、超时和抖动做统一收敛。
- `fallbacks` + `cooldown_time`：主模型异常时自动切到降级模型，并对异常部署做短暂冷却。
