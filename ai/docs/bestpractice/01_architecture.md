# 架构设计：模块化与解耦

**1. 模型无关性设计 (Model Agnostic)**

* **原则**：不要在业务代码里把模型写死（比如到处写 `gpt-4o`）。
* **实践**：设计一个 `ModelRouter` 层。今天用 OpenAI，明天可能因为数据隐私要换 DeepSeek 或本地 Llama 3。
* **进阶**：使用“大小模型搭配”。简单的意图识别用小模型（GPT-4o-mini/Haiku/本地7B），复杂的逻辑推理用大模型。

**2. 结构化输出优先 (Structured Output First)**

* **原则**：**绝对不要**试图用正则表达式去解析 LLM 返回的自然语言。
* **实践**：
  * **强制使用 Function Calling / Tool Use**：哪怕你不需要调用外部工具，也定义一个 JSON Schema 强迫 LLM 按格式填充。
  * **Pydantic 是神器**：在 LangChain 中使用 `PydanticOutputParser` 或 `.with_structured_output(MyClass)`。这能自动把 JSON 转成 Python 对象，并进行类型校验。

**3. 缓存策略 (Caching Strategy)**

* **原则**：LLM 调用既贵又慢，能不调就不调。
* **实践**：
  * **精确缓存**：完全相同的输入，直接返回上次结果（Redis/Memcached）。
  * **语义缓存 (Semantic Cache)**：如果用户问“推荐个手机”和“手机推荐”意思一样，直接返回缓存。可以使用向量数据库来实现语义相似度匹配。
