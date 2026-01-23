# 工具与生态：从组件到平台

工具不等于能力。生产级 LLM 应用里，工具的价值是把“不确定性”收敛到可观测、可回滚、可治理的工程系统里。

**1. 选型原则**

* **先定义问题，再选工具**：目标是质量/成本/延迟/合规的哪一项？别为了“用框架”而用框架。
* **避免强耦合**：优先把“模型调用、向量库、评估、观测”做成可替换组件（接口/适配层）。
* **把可观测性当硬要求**：没有 trace/metrics 的组件，上线后基本等于盲飞。
* **开源 + 托管两手准备**：核心链路尽量可自建，关键依赖要有替代方案（供应商/成本/合规变化很常见）。

**2. 组件地图（你通常需要的能力）**

* **模型网关/路由**：统一鉴权、限流、重试、降级、成本统计；支持多模型与多供应商。
* **RAG 组件**：文档解析/清洗、向量库、关键词检索（BM25）、重排序、引用与溯源。
* **Evals**：离线批量评估、回归测试、对比实验、质量门禁（CI/CD）。
* **Guardrails**：注入防护、PII 脱敏、内容安全策略、工具白名单/黑名单。
* **观测与治理**：trace、指标、日志、反馈闭环、审计与多租户隔离。
* **应用平台**：当你需要“低代码交付/业务方自助配置/多应用统一治理”，平台类（如 Dify）会更合适。

**3. 工具链接的维护建议**

* 每章末尾只放“官方 GitHub 链接”，避免链接漂移。
* 链接旁边加一句用途（例如“Evals/Trace/向量库”），便于快速筛选。
* 如果团队规模较大，建议再单独维护一份 `tools-index.md`（按类别集中维护），章节里引用即可。

## 相关工具链接

- 模型网关/路由：<https://github.com/BerriAI/litellm>
- 编排框架：<https://github.com/langchain-ai/langchain>，<https://github.com/run-llama/llama_index>
- 文档解析/清洗：<https://github.com/Unstructured-IO/unstructured>
- 向量数据库：<https://github.com/pgvector/pgvector>，<https://github.com/qdrant/qdrant>，<https://github.com/milvus-io/milvus>
- Evals：<https://github.com/explodinggradients/ragas>，<https://github.com/confident-ai/deepeval>，<https://github.com/promptfoo/promptfoo>
- 观测与 Trace：<https://github.com/langfuse/langfuse>，<https://github.com/Helicone/helicone>
- Guardrails：<https://github.com/NVIDIA/NeMo-Guardrails>，<https://github.com/guardrails-ai/guardrails>
- 平台：<https://github.com/langgenius/dify>
