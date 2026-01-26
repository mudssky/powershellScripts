# LangChain 生态最佳实践

LangChain 的核心价值是把“Prompt + 模型 + 工具 + 记忆 + RAG”组合成可复用的链路；但在生产环境要避免“过度抽象”和“隐式魔法”。

**1. 先 Chain 后 Agent（能确定就别赌博）**

* **优先用 LCEL/Runnables** 把流程写成明确的管线：输入是什么、输出是什么、哪里可能失败。
* 只有当任务需要动态规划（多步推理、工具选择不确定）时，再引入 Agent；并设置循环上限、预算与超时。

**2. Structured Output First（结构化输出优先）**

* 生产环境尽量让模型输出可校验的结构（JSON Schema / Pydantic），不要依赖自然语言再解析。
* 对工具调用场景，工具的输入/输出都要做 Schema 校验与错误处理（可重试、可降级、可观测）。

**3. RAG 组件化（Retriever/重排/引用）**

* 把“切分->索引->检索->重排->引用->生成”拆成可替换模块，避免把所有逻辑塞到一个 Chain 里。
* 给 `Document` 的 `metadata` 设计统一规范（来源、时间、权限、版本、分段位置），否则无法做溯源与权限控制。

**4. 线上工程要点（并发、超时、观测、缓存）**

* **并发与超时**：对检索、重排、LLM 调用分别设置 timeout；对外部工具调用做隔离与熔断。
* **观测**：把 `prompt_id@version`、retriever 命中、rerank 结果、工具调用参数摘要写入 trace，方便定位质量问题。
* **缓存**：对“确定性结果”和“高频问答”优先做缓存；对语义缓存要考虑权限与过期策略。

**5. 用 LangGraph 管状态机（复杂 Agent 的可控解法）**

* 当你需要可控的多步骤编排（审批、路由、回退、人工介入），用图（Graph）表达流程，通常比“自由 Agent”更稳。

## 相关工具链接

- LangChain：<https://github.com/langchain-ai/langchain>
- LangGraph：<https://github.com/langchain-ai/langgraph>
- LangServe（把 chain/graph 服务化）：<https://github.com/langchain-ai/langserve>
- LangSmith SDK（Trace/Evals 接入）：<https://github.com/langchain-ai/langsmith-sdk>
