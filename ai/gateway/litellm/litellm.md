# LiteLLM 网关说明

这个目录用于启动一个基于 LiteLLM Proxy 的统一模型网关，当前配置会把客户端传入的模型名透传到 NewAPI。

相关文件职责如下：

- `newapi.yaml`：LiteLLM 代理配置，定义模型透传和 `master_key`。
- `compose.yaml`：LiteLLM 容器模板，定义镜像、端口、挂载和默认环境变量。
- `start.ps1`：统一入口，封装常用 `docker compose` 操作。
- `../.env.local`：本地私有环境变量，保存 `NEWAPI_KEY`、`NEWAPI_API_BASE`、`LITELLM_MASTER_KEY`、可选 `DATABASE_URL`。

## 环境变量

建议先在 `ai/gateway/.env.local` 中配置以下值：

```dotenv
NEWAPI_KEY=sk-xxxx
NEWAPI_API_BASE=https://example.com
LITELLM_MASTER_KEY=sk-litellm-123456
DATABASE_URL=postgresql://postgres:12345678@host.docker.internal:5432/litellm
```

说明：

- `NEWAPI_KEY`：NewAPI 的访问密钥。
- `NEWAPI_API_BASE`：NewAPI 的 OpenAI 兼容接口地址。
- `LITELLM_MASTER_KEY`：LiteLLM Proxy 对外暴露的网关密钥。
- `DATABASE_URL`：LiteLLM 的数据库连接串；如果未配置，会回退到默认的宿主机 PostgreSQL 地址。

## 启动方式

推荐直接使用 `start.ps1`：

```powershell
./ai/gateway/litellm/start.ps1
```

默认等价于：

```powershell
docker compose --env-file ai/gateway/.env.local `
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
docker compose --env-file ai/gateway/.env.local `
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
  -d "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}"
```

## 配置说明

当前 `newapi.yaml` 的关键点：

- `model_name: "*"` 允许客户端传入任意模型名。
- `model: "openai/{{ model }}"` 会把客户端的模型名透传给下游 NewAPI。
- `api_base`、`api_key`、`master_key` 都从容器环境变量读取，便于本地通过 `.env.local` 管理敏感值。
