## 🚀 核心命令 (Basic CLI)

最常用的命令行操作。

| 命令 | 说明 | 示例 |
| :--- | :--- | :--- |
| **`ollama run`** | 运行并进入交互模式 (如果没有模型会自动下载) | `ollama run llama3` |
| **`ollama pull`** | 仅下载/更新模型，不运行 | `ollama pull qwen2` |
| **`ollama list`** | 列出本地已下载的模型 | `ollama list` |
| **`ollama rm`** | 删除本地模型 | `ollama rm llama2` |
| **`ollama cp`** | 复制模型 (常用于重命名或备份) | `ollama cp llama3 my-model` |
| **`ollama ps`** | 查看当前正在显存中运行的模型 | `ollama ps` |
| **`ollama show`** | 显示模型详情 (Modelfile, 参数等) | `ollama show --modelfile llama3` |

### 交互模式下的快捷指令
在 `ollama run <model>` 进入对话框后使用：
*   `/?`: 获取帮助
*   `/bye` 或 `Ctrl + D`: 退出对话
*   `/set parameter seed 123`: 临时设置参数
*   `/show info`: 查看当前模型信息
*   `"""`: 输入多行文本

---

## ⚙️ 模型定制 (Modelfile)

创建自定义的角色（System Prompt）或调整参数。

**1. 创建文件 `Modelfile`**
```dockerfile
FROM llama3

# 设置温度 (越高越有创造力，越低越严谨)
PARAMETER temperature 0.7

# 设置上下文窗口大小 (默认 2048)
PARAMETER num_ctx 4096

# 设置系统提示词 (核心灵魂)
SYSTEM """
你是一个资深的Linux运维专家。
请只回答与Linux、Shell、网络配置相关的问题。
回答要简洁，并优先给出代码示例。
"""
```

**2. 编译模型**
```bash
# 语法: ollama create <新模型名> -f <Modelfile路径>
ollama create linux-expert -f ./Modelfile
```

**3. 运行新模型**
```bash
ollama run linux-expert
```

---

## 🔌 API 调用 (cURL 示例)

Ollama 默认监听 `11434` 端口。

**1. 生成回复 (Generate - 流式)**
```bash
curl http://localhost:11434/api/generate -d '{
  "model": "llama3",
  "prompt": "为什么天空是蓝色的？"
}'
```

**2. 聊天模式 (Chat - 类似 OpenAI)**
```bash
curl http://localhost:11434/api/chat -d '{
  "model": "llama3",
  "messages": [
    { "role": "user", "content": "你好，介绍一下你自己" }
  ],
  "stream": false
}'
```

**3. 获取 Embeddings (用于 RAG)**
```bash
curl http://localhost:11434/api/embeddings -d '{
  "model": "nomic-embed-text",
  "prompt": "Hello world"
}'
```

---

## 🛠️ 服务管理 (Linux Systemd)

针对 Linux 系统的后台服务管理。

| 操作 | 命令 |
| :--- | :--- |
| **启动服务** | `sudo systemctl start ollama` |
| **停止服务** | `sudo systemctl stop ollama` |
| **重启服务** | `sudo systemctl restart ollama` |
| **查看状态** | `sudo systemctl status ollama` |
| **查看日志** | `journalctl -u ollama -f` (排错神器) |

---

## 环境变量 (Environment Variables)

配置 Ollama 行为的关键变量。
*在 Linux 中通过 `sudo systemctl edit ollama.service` 配置*。

| 变量名 | 默认值 | 说明 |
| :--- | :--- | :--- |
| **`OLLAMA_HOST`** | `127.0.0.1` | 设置为 `0.0.0.0` 可允许远程访问 |
| **`OLLAMA_MODELS`** | `~/.ollama/models` | 修改模型存储路径 (如移到大硬盘 `/data/ollama`) |
| **`OLLAMA_KEEP_ALIVE`**| `5m` | 模型加载在显存中的保留时间 (可设为 `24h` 或 `-1` 永久) |
| **`OLLAMA_NUM_PARALLEL`** | `1` | 允许并发处理的请求数量 |
| **`OLLAMA_MAX_LOADED_MODELS`** | `1` | 允许同时加载在显存中的模型数量 |
| **`OLLAMA_ORIGINS`** | `*` | 跨域设置 (CORS)，限制允许访问的域名 |

---

## 📦 常用热门模型 (Model Library)

无需死记硬背，去 [ollama.com/library](https://ollama.com/library) 查看。

| 模型名 | 特点 | 适用场景 |
| :--- | :--- | :--- |
| **`llama3`** (8b/70b) | Meta出品，目前最强开源模型之一 | 通用助手，逻辑强，速度快 |
| **`gemma2`** (9b/27b) | Google出品，性能优异 | 通用，知识库丰富 |
| **`qwen2.5`** | 阿里出品，**中文能力极强** | 中文对话，写作，代码 |
| **`mistral`** | 欧洲团队，高性价比 | 英语任务，逻辑推理 |
| **`codellama`** | 专精代码 | 代码补全，Debug |
| **`llava`** | 多模态 (Multimodal) | **图片识别**，图像描述 |
| **`nomic-embed-text`** | 嵌入模型 | 用于构建 RAG (知识库) 系统 |

---

## ⚠️ 远程访问安全清单

如果你配置了远程访问，请核对以下三点：

1.  **绑定地址**：`OLLAMA_HOST=0.0.0.0`
2.  **防火墙**：`sudo ufw allow 11434` (仅允许可信 IP) 或配置 Nginx 端口。
3.  **认证**：**必须**配置 Nginx Basic Auth 或 LiteLLM (因为 Ollama 原生无密码)。

---

### 一键卸载 (Linux)
如果需要重装或清除：
```bash
sudo systemctl stop ollama
sudo systemctl disable ollama
sudo rm /etc/systemd/system/ollama.service
sudo rm -rf /usr/share/ollama /usr/local/bin/ollama
sudo userdel ollama
sudo groupdel ollama
```