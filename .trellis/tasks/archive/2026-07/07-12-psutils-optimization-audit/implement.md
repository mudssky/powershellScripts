# psutils 优化审计执行计划

## Parent Checklist

- [x] 审计源码、manifest、测试、文档、示例、消费者和历史任务。
- [x] 确认 PowerShell 7.4+ / Core 兼容目标。
- [x] 确认用户 API 兼容、内部泄漏可收口的策略。
- [x] 确认保留 `index.psm1` 弃用 shim。
- [x] 创建四个可独立验收的子任务并写入依赖。
- [x] 用户审阅父任务和子任务规划。
- [x] 启动并完成 `07-12-psutils-core-contract`。
- [ ] 按依赖完成文档、API 边界和运行时加固子任务。
- [ ] 执行父任务最终集成审查并归档任务树。

## Start Rule

父任务不直接 `task.py start`。规划批准后，首先激活 `07-12-psutils-core-contract`；每个子任务完成质量门和提交后再启动下一个。

## Final Gate

```powershell
pnpm qa
pnpm test:pwsh:all
```

最终复核：manifest 与真实导出一致、README/示例无漂移、Profile 延迟加载边界保持、没有遗留失效入口。
