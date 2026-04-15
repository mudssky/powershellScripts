# TensorZero 网关说明

这个目录提供一个基于 TensorZero 的生产级 Qwen 模板，默认包含：

- `tensorzero-gateway`：推理与反馈 API，宿主机端口 `34400`
- `tensorzero-ui`：管理与观测 UI，宿主机端口 `34401`
- `clickhouse`：推理、反馈和观测数据存储，不默认暴露到宿主机
- `valkey`：自定义限流状态后端，不默认暴露到宿主机

相关文件职责如下：

- `compose.yaml`：TensorZero 全部服务的 compose 模板。
- `start.ps1`：统一入口，封装常用 `docker compose` 操作。
- `.env.example`：开发环境变量示例。
- `.env.production.example`：生产环境变量示例。
- `tensorzero.toml`：生产级网关配置示例，包含百炼接入、降级、重试和限流规则。
- `.env.local`：本地私有环境变量覆盖文件，可选。

## 环境变量

建议先在 `ai/gateway/tensorzero/.env.local` 中配置以下值：

```dotenv
TENSORZERO_GATEWAY_IMAGE=tensorzero/gateway
TENSORZERO_UI_IMAGE=tensorzero/ui
TENSORZERO_CLICKHOUSE_IMAGE=clickhouse/clickhouse-server:lts
TENSORZERO_VALKEY_IMAGE=valkey/valkey:8-alpine
TENSORZERO_GATEWAY_PORT=34400
TENSORZERO_UI_PORT=34401
DASHSCOPE_API_KEY=sk-xxxx
TENSORZERO_CLICKHOUSE_DB=tensorzero
TENSORZERO_CLICKHOUSE_USER=tensorzero
TENSORZERO_CLICKHOUSE_PASSWORD=change-me
TENSORZERO_CLICKHOUSE_URL=http://tensorzero:change-me@clickhouse:8123/tensorzero
TENSORZERO_GATEWAY_URL=http://tensorzero-gateway:3000
TENSORZERO_VALKEY_URL=redis://valkey:6379/0
```

其中：

- `DASHSCOPE_API_KEY`：阿里百炼 API Key，供 `tensorzero.toml` 里的 OpenAI 兼容提供方配置使用。
- `TENSORZERO_GATEWAY_PORT`：宿主机访问 TensorZero Gateway 的端口，默认 `34400`。
- `TENSORZERO_UI_PORT`：宿主机访问 TensorZero UI 的端口，默认 `34401`。
- `TENSORZERO_CLICKHOUSE_*`：ClickHouse 初始化账号、密码和数据库。
- `TENSORZERO_CLICKHOUSE_URL`：Gateway / UI 内部访问 ClickHouse 的连接串；如果你修改了用户、密码或数据库名，要同步改这个值。
- `TENSORZERO_VALKEY_URL`：自定义限流状态后端；启用 `rate_limiting.rules` 时必须存在。

如果你要准备生产环境，可以复制 `./.env.production.example` 再按实际环境改值。

## 启动方式

推荐直接使用：

```powershell
./ai/gateway/tensorzero/start.ps1
```

默认等价于：

```powershell
docker compose --env-file ai/gateway/tensorzero/.env.local `
  -f ai/gateway/tensorzero/compose.yaml `
  --project-directory ai/gateway/tensorzero `
  up -d
```

常用命令：

```powershell
./ai/gateway/tensorzero/start.ps1
./ai/gateway/tensorzero/start.ps1 down
./ai/gateway/tensorzero/start.ps1 restart
./ai/gateway/tensorzero/start.ps1 logs --tail 100
./ai/gateway/tensorzero/start.ps1 ps
./ai/gateway/tensorzero/start.ps1 pull
```

## 访问方式

默认地址：

```text
Gateway: http://127.0.0.1:34400
UI:      http://127.0.0.1:34401
```

最小推理请求示例：

```powershell
curl http://127.0.0.1:34400/inference `
  -H "Content-Type: application/json" `
  -d "{\"function_name\":\"chat_prod\",\"input\":{\"messages\":[{\"role\":\"user\",\"content\":\"你好，介绍一下 TensorZero\"}]}}"
```

## 配置说明

`tensorzero.toml` 当前提供的是一套生产向示例：

- `qwen_plus_prod`：主模型，直连阿里百炼 `qwen-plus`
- `qwen_flash_fallback`：降级模型，直连阿里百炼 `qwen-flash`
- `chat_prod`：默认生产聊天函数，优先主模型，失败后顺序降级
- `retries` + `timeouts`：在 provider 和 variant 两层分别约束重试和超时
- `rate_limiting.rules`：示例化地展示全局总量保护与按 `tenant_id` 的细粒度限流

注意：

- `tokens_per_hour` 规则要求请求中显式传 `max_tokens`，否则无法对 token 做保守预估。
- 如果你要让按租户限流生效，请在请求里传 `tags.tenant_id`。

这个模板的目标是先跑通本地网关、UI、观测链路和基础限流。生产环境通常还会继续补：

- 更多函数与变体
- fallback / A/B / evaluation 策略
- 更严格的 ClickHouse / Valkey 账号和网络隔离
- 反向代理、HTTPS 与外部身份认证
