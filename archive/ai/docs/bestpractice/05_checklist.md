# 总结 Checklist

如果你在做一个生产级的 LLM 应用，问自己这 5 个问题：

1. **可观测性**：如果有用户投诉回答很傻，我能在一分钟内找到是哪一步（检索错了？还是 LLM 幻觉了？）出的问题吗？（LangSmith）
2. **评估体系**：我改了一段 Prompt，怎么保证没有导致其他 10 个场景变差？（Regression Testing）
3. **延迟优化**：是否使用了流式输出（Streaming）？用户看到第一个字的时间（TTFT）是多少？
4. **成本控制**：是否统计了 Token 用量？有没有死循环烧钱的风险？
5. **数据闭环**：用户的反馈（点赞/点踩）有没有存下来？这些数据应该成为你下一次优化 Prompt 或微调模型的燃料。

## 相关工具链接

- Trace / 可观测性：<https://github.com/langchain-ai/langsmith-sdk>，<https://github.com/langfuse/langfuse>，<https://github.com/Helicone/helicone>
- 可观测性标准：<https://github.com/open-telemetry/opentelemetry-collector>，<https://github.com/open-telemetry/opentelemetry-python>
