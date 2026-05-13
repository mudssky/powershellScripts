# Coding Plan Window Warmer

这个目录提供一个独立的 Coding Plan 窗口预热脚本。它通过 LiteLLM Python SDK 直连上游 OpenAI 兼容端点发送轻量请求，不走本机 LiteLLM Proxy 路由，因此不会触发 LiteLLM 的 fallback。

## 文件说明

- `pyproject.toml` / `uv.lock`：uv 项目依赖声明与锁文件，包含 LiteLLM SDK。
- `window_warmer.py`：长期运行的预热脚本入口。
- `window_warmer_lib/`：配置、调度、目标检查和运行循环拆分模块。
- `window-warmer.toml`：预热配置，支持多个 Coding Plan。
- `window-warmer.pm2.config.cjs`：PM2 进程管理配置。
- `.env.example`：本地 API key 示例；复制为 `.env.local` 后填写真实密钥。
- `tests/test_window_warmer.py`：标准库 `unittest` 回归测试。

## 工作方式

脚本会按配置计算每个 `[[plans]]` 的下一次预热时间，并在触发前按 `[target]` 配置检查：

1. `container_name` 指定的本机 Docker 容器是否处于 running 状态；为空时跳过容器检查。
2. `health_path` 指定的目标 API 健康端点是否可访问；为空时跳过 API 健康检查。
3. `api_key_env` 指定的 API key 是否能从环境变量或 `env_file` 读取；为空时不发送鉴权头。

只有这些条件满足后，脚本才会通过 `litellm.completion(api_base=base_url, api_key=...)` 直连目标端点发送轻量预热请求。默认配置示例直连智谱 Coding Plan 官方 OpenAI 兼容端点，同时用 `container_name = "litellm"` 作为“本机网关已启动”的可选前置条件。

如果不希望依赖本机 LiteLLM 容器启动状态，可以删除 `container_name`，或把它配置为空字符串。

## 密钥与模型

模型名写在 `window-warmer.toml` 的 `[[plans]].model` 中。使用 LiteLLM SDK 直连 OpenAI 兼容上游时，建议写成带 provider 前缀的形式，例如：

```toml
[[plans]]
model = "openai/GLM-5.1"
```

API key 由 `[target].api_key_env` 指定变量名，脚本读取顺序是：

1. 当前进程环境变量，例如 shell 里已有 `Z_AI_API_KEY=...`。
2. `[target].env_file` 指向的 dotenv 文件，例如默认 `.env.local`。

默认配置等价于读取同目录 `.env.local` 中的 `Z_AI_API_KEY`：

```dotenv
Z_AI_API_KEY=sk-zai-dev-xxxx
```

本地第一次使用时可以创建自己的密钥文件：

```bash
cd ai/coding/window-warmer
cp .env.example .env.local
```

## 直接运行

```bash
cd ai/coding/window-warmer
uv run python window_warmer.py --config window-warmer.toml
```

查看下一次触发时间：

```bash
cd ai/coding/window-warmer
uv run python window_warmer.py --config window-warmer.toml --print-next
```

立即对所有启用 plan 试跑一次：

```bash
cd ai/coding/window-warmer
uv run python window_warmer.py --config window-warmer.toml --once
```

只打印，不发送真实请求：

```bash
cd ai/coding/window-warmer
uv run python window_warmer.py --config window-warmer.toml --once --dry-run
```

## PM2 管理

启动：

```bash
pm2 start ai/coding/window-warmer/window-warmer.pm2.config.cjs
```

查看日志：

```bash
pm2 logs coding-window-warmer
```

执行日志会包含调度触发、容器检查、API key 来源、健康检查、请求发送、重试、成功/失败和耗时；不会输出 prompt、API key、请求头或完整请求体。

重启：

```bash
pm2 restart coding-window-warmer
```

停止：

```bash
pm2 stop coding-window-warmer
```

保存当前 PM2 进程列表：

```bash
pm2 save
```

配置开机恢复：

```bash
pm2 startup
pm2 save
```

## 多 Coding Plan

每个 `[[plans]]` 表示一个独立预热计划。不同 plan 可以使用不同模型、prompt、调度模式和重试策略。

固定时间点模式：

```toml
[[plans]]
name = "glm-coding-plan"
enabled = true
model = "openai/GLM-5.1"
prompt = "你好吗"
schedule_mode = "fixed_times"
times = ["08:00", "13:00", "18:00", "23:00"]
jitter_seconds = 120
retry_count = 1
```

窗口间隔模式：

```toml
[[plans]]
name = "another-coding-plan"
enabled = true
model = "openai/another-model"
prompt = "你好吗"
schedule_mode = "interval"
start_time = "08:00"
window = "5h"
jitter_seconds = 120
retry_count = 1
```

`interval` 模式会从锚点开始按窗口时长连续推导，例如 `08:00 + 5h` 会得到 `08:00`、`13:00`、`18:00`、`23:00`、次日 `04:00`。

## 配置说明

- `[target].name`：目标服务诊断名称，只用于日志。
- `[target].base_url`：直连上游 OpenAI 兼容 API 的基础地址。
- `[target].container_name`：可选 Docker 容器名；默认示例为 `litellm`。
- `[target].api_key_env`：可选 API key 环境变量名；默认示例为 `Z_AI_API_KEY`。
- `[target].env_file`：相对当前 TOML 文件的 dotenv 文件路径；默认示例指向同目录 `.env.local`。
- `[target].health_path`：可选健康检查路径；默认示例为 `/models`。
- `[scheduler].default_jitter_seconds`：plan 未单独配置时使用的随机延迟上限。
- `[scheduler].default_retry_count`：plan 未单独配置时的失败重试次数。
- `[[plans]].model`：LiteLLM SDK 模型名。直连 OpenAI 兼容上游时建议显式使用 `openai/<模型名>`。
- `[[plans]].max_tokens`：预热请求的最大输出 token，默认配置保持较小值。

## 测试

```bash
cd ai/coding/window-warmer
uv run python -m unittest discover \
  -s tests \
  -p 'test_*.py'
```
