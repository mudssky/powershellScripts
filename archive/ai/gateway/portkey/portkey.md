# Portkey 网关说明

这个目录提供一个基于 Portkey OSS Gateway 的 NewAPI 接入模板，默认把服务暴露到宿主机 `34200` 端口。

相关文件职责如下：

- `compose.yaml`：Portkey 容器模板，定义镜像与端口映射。
- `start.ps1`：统一入口，封装常用 `docker compose` 操作。
- `.env.example`：开发环境变量示例。
- `.env.production.example`：生产环境变量示例。
- `newapi.config.example.json`：面向 NewAPI 的生产配置对象示例，包含超时、重试和降级策略。
- `.env.local`：本地私有环境变量覆盖文件，可选。

## 环境变量

Portkey OSS Gateway 的基础启动几乎不依赖服务端环境变量；这个目录里的 `.env.local` 主要用于覆盖镜像、端口，以及给本地 SDK / 脚本示例提供 NewAPI 参数：

```dotenv
PORTKEY_IMAGE=portkeyai/gateway:latest
PORTKEY_HOST_PORT=34200
NEWAPI_API_BASE=https://newapi.example.com/v1
NEWAPI_API_KEY=sk-xxxx
```

其中 `NEWAPI_API_BASE` 与 `NEWAPI_API_KEY` 不会被 compose 自动消费，它们主要供 `newapi.config.example.json` 或本地调用脚本替换占位值时参考。

如果你要准备生产环境，可以复制 `./.env.production.example` 再按实际发布策略调整。

## 启动方式

推荐直接使用：

```powershell
./ai/gateway/portkey/start.ps1
```

默认等价于：

```powershell
docker compose --env-file ai/gateway/portkey/.env.local `
  -f ai/gateway/portkey/compose.yaml `
  --project-directory ai/gateway/portkey `
  up -d
```

常用命令：

```powershell
./ai/gateway/portkey/start.ps1
./ai/gateway/portkey/start.ps1 down
./ai/gateway/portkey/start.ps1 restart
./ai/gateway/portkey/start.ps1 logs --tail 100
./ai/gateway/portkey/start.ps1 ps
./ai/gateway/portkey/start.ps1 pull
```

## 访问方式

默认地址：

```text
http://127.0.0.1:34200
```

Portkey Web 控制台通常可从以下路径访问：

```text
http://127.0.0.1:34200/public/
```

OpenAI 兼容请求示例：

```powershell
curl http://127.0.0.1:34200/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "x-portkey-provider: openai" `
  -H "x-portkey-custom-host: https://newapi.example.com/v1" `
  -H "Authorization: Bearer <NEWAPI_API_KEY>" `
  -d "{\"model\":\"qwen-plus\",\"messages\":[{\"role\":\"user\",\"content\":\"你好，介绍一下 Portkey\"}]}"
```

## 配置说明

`newapi.config.example.json` 提供了一个面向 NewAPI 的生产级配置对象示例，重点展示：

- 通过 `custom_host` 把 Portkey 路由到指定的 NewAPI OpenAI 兼容入口。
- 通过 `retry` 对 408 / 429 / 5xx 做自动重试，并尊重上游 `Retry-After`。
- 通过 `strategy.mode = "fallback"` 在 `qwen-plus` 失败时降级到 `qwen-flash`。
- 通过 `request_timeout` 控制单次请求的超时时间。

这个文件不会被 compose 自动挂载，它更适合：

- 作为 SDK 中 `config` 参数的参考模板。
- 作为 `x-portkey-config` 请求头的 JSON 样板。
- 作为团队统一的 NewAPI 路由、fallback、retry 模板。
