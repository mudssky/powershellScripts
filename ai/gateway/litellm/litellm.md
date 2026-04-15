最简单理解：

**LiteLLM = 用一套统一的 OpenAI 风格接口，去调用很多不同的大模型提供商**。
比如 OpenAI、Azure OpenAI、Anthropic、Bedrock、Ollama、vLLM 等。

它常见有两种用法：

1. **Python 里直接调用 LiteLLM SDK**
2. **启动 LiteLLM Proxy，当成统一网关来用**

---

# 1）直接在 Python 里用 LiteLLM

## 安装

```powershell
pip install litellm
```

如果你用的是 OpenAI，先在 Windows PowerShell 里设置环境变量：

```powershell
$env:OPENAI_API_KEY="你的_openai_key"
```

---

## 最小可运行示例

```python
from litellm import completion

resp = completion(
    model="openai/gpt-4o",
    messages=[
        {"role": "system", "content": "你是一个 helpful assistant"},
        {"role": "user", "content": "用一句话解释什么是 LiteLLM"}
    ]
)

print(resp.choices[0].message.content)
```

---

## 流式输出

```python
from litellm import completion

response = completion(
    model="openai/gpt-4o",
    messages=[{"role": "user", "content": "写一个简短的自我介绍"}],
    stream=True
)

for chunk in response:
    content = chunk.choices[0].delta.content
    if content:
        print(content, end="")
```

---

## 异步调用

```python
import asyncio
from litellm import acompletion

async def main():
    resp = await acompletion(
        model="openai/gpt-4o",
        messages=[{"role": "user", "content": "你好，介绍一下异步调用"}]
    )
    print(resp.choices[0].message.content)

asyncio.run(main())
```

---

## Embedding 示例

```python
from litellm import embedding

resp = embedding(
    model="text-embedding-3-small",
    input=["你好，LiteLLM"]
)

print(len(resp.data[0]["embedding"]))
```

---

# 2）用 LiteLLM Proxy 当统一模型网关

这种方式很适合：

- 你有多个模型供应商
- 想统一 API
- 想让 Java / Node.js / Python 都走同一个入口
- 想加鉴权、限流、日志、路由

---

## 安装 Proxy

```powershell
pip install "litellm[proxy]"
```

---

## 写一个最小 `config.yaml`

```yaml
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: "os.environ/OPENAI_API_KEY"

general_settings:
  master_key: sk-1234
```

这里要注意：

- `model_name`：你暴露给客户端看的模型名
- `litellm_params.model`：真实后端模型名

---

## 启动代理

先设置环境变量：

```powershell
$env:OPENAI_API_KEY="你的_openai_key"
```

再启动：

```powershell
litellm --config config.yaml
```

默认一般会跑在：

```text
http://0.0.0.0:4000
```

---

## 用 curl 调代理

```powershell
curl http://127.0.0.1:4000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer sk-1234" `
  -d "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"你好，介绍一下你自己\"}]}"
```

---

## 用 OpenAI SDK 调 LiteLLM Proxy

```powershell
pip install openai
```

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-1234",
    base_url="http://127.0.0.1:4000"
)

resp = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "LiteLLM Proxy 是什么？"}]
)

print(resp.choices[0].message.content)
```

---

# 3）模型名怎么写？

LiteLLM 里通常是这种格式：

```text
provider/model
```

常见例子：

- `openai/gpt-4o`
- `bedrock/anthropic.claude-instant-v1`
- `azure/你的部署名`
- `openai/某个兼容 OpenAI 协议的模型`

如果你接的是 **OpenAI 兼容接口**（比如某些自建网关、vLLM），一般还需要：

- `api_base`
- `api_key`
- `openai/` 前缀

例如：

```yaml
model_list:
  - model_name: local-model
    litellm_params:
      model: openai/facebook/opt-125m
      api_base: http://127.0.0.1:8000/v1
      api_key: "none"
```

---

# 4）常见问题

## 1. 报 401 / Unauthorized

通常是：

- 环境变量没设置成功
- Proxy 的 `master_key` 不匹配
- 真实供应商 key 错了

---

## 2. 报 model not found

通常是：

- 你请求的 `model` 和 `config.yaml` 里的 `model_name` 不一致
- 或者 `litellm_params.model` 写错了

---

## 3. 想切换供应商怎么办？

通常只需要改：

- `model=...`
- 对应的 API Key 环境变量
- 如果是私有服务，再加 `api_base`

这正是 LiteLLM 的核心价值。

---

# 5）建议你这样入门

如果你是第一次用，建议按这个顺序：

### 方案 A：只想在 Python 里快速调用

直接用：

- `pip install litellm`
- `completion(...)`

### 方案 B：你想做统一网关

直接用：

- `pip install "litellm[proxy]"`
- 写 `config.yaml`
- `litellm --config config.yaml`
