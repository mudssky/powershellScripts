# RAG（检索增强生成）工程化

简单的 RAG（切分->向量化->检索->生成）在生产环境通常效果很差，需要引入高级策略：

**1. 混合检索 (Hybrid Search)**

* **痛点**：向量检索擅长语义，但对专有名词（如产品型号 "iPhone 16 Pro"）经常失效。
* **最佳实践**：**向量检索 (Vector Search) + 关键词检索 (BM25)** 同时进行，然后用加权算法（Reciprocal Rank Fusion, RRF）合并结果。

**2. 重排序 (Re-ranking)**

* **痛点**：检索回来的 Top-5 文档可能只有第 4 个是有用的，但 LLM 对开头和结尾的内容关注度最高（Lost in the Middle 现象）。
* **最佳实践**：先检索出 Top-50，然后用专门的 **Re-rank 模型**（如 BGE-Reranker, Cohere Rerank）精排选出 Top-5。这能显著提升准确率。

**3. 数据清洗 ETL 比 Prompt 更重要**

* **原则**：Garbage In, Garbage Out。
* **实践**：不要直接扔 PDF 进去。要去掉页眉页脚、解析表格、把图片转文字（OCR）。如果你的知识库质量差，换 GPT-5 也没救。

## 相关工具链接

- 文档解析/清洗：<https://github.com/Unstructured-IO/unstructured>，<https://github.com/apache/tika>
- 向量数据库：<https://github.com/pgvector/pgvector>，<https://github.com/qdrant/qdrant>，<https://github.com/milvus-io/milvus>，<https://github.com/weaviate/weaviate>，<https://github.com/chroma-core/chroma>
- 关键词检索（BM25）：<https://github.com/elastic/elasticsearch>，<https://github.com/opensearch-project/OpenSearch>
- Embedding/重排序（含 BGE）：<https://github.com/FlagOpen/FlagEmbedding>
