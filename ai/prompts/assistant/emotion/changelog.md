
# 版本演进记录 (Changelog)

- [v1版本](./deprecated/01love-chat-master.md): **恋爱聊天大师** - 初始版本，纯指令驱动。侧重于高姿态的话术建议、潜台词分析和心理博弈。
- [v2版本](./deprecated/02the-ultimate-wingman.md): **金牌恋爱僚机** - 角色升级。从“教导者”转变为用户的“战友”，引入“先肯定、再优化”的沟通原则，降低使用门槛，增强实用性。 因为v1版本过于高姿态，导致我们任何一句话都会被他反驳，因此升级到v2更友好
- [v3版本](./03the-ultimate-wingman.md): **自动化集成版** - 引入文件系统。通过绝对路径自动读取用户的 `daily_notes` 和 `herprofile.md`，使建议具备长期的上下文记忆。
- [v4版本](./04the-ultimate-wingman.md): **智能缓存版** - 性能优化。引入 `context_cache.md` 缓存机制，减少对原始大文件的频繁读取，并增加 `[MODE]` 标记以明确当前情报来源。 因为v3版本多个模型每次都要重复调用mcp，会有多余token消耗。优化后，第一个模型用便宜的生成缓存，减少后续消耗。
- [v5版本](./05the-ultimate-wingman.md): 新增myprofile.md，用于存储用户的个人信息。
