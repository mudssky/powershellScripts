# 实施计划

## 修改步骤

1. 为根 `install.ps1` 到 `Invoke-InstallOrchestrator` 增加仅 Text 模式启用的进度开关。
2. 扩展叶子执行器：启动时输出安全步骤行，使用有限等待循环生成 15 秒 heartbeat，并在异常/中断时清理仍存活的子进程树。
3. 新增 Pester fixture：耗时叶子在退出前可见进度；JSON 模式无进度污染；中断清理不遗留进程。
4. 更新安装编排 spec 的 Text/JSON 进度合同和错误矩阵。

## 验证

1. 安装编排窄测。
2. `pnpm provision:core:preview -SkipStep verify`。
3. JSON 单文档 fixture/CLI 测试。
4. `pnpm qa`。
5. `pnpm test:pwsh:all`；Docker 不可用时执行 `pnpm test:pwsh:full` 并说明 Linux 边界。

## 风险与回滚

- 风险：进度文本污染 JSON stdout。通过只在 Text 模式开启且写 stderr规避。
- 风险：中断后遗留下载进程。异常路径显式终止进程树并以测试锁定。
- 回滚：删除进度开关、等待循环和对应测试；原同步等待语义恢复。
