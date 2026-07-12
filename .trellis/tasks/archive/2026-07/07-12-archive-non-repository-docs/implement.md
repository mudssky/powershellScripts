# 实施计划

- [x] 读取 `trellis-before-dev`、`.trellis/spec/infra/repository-archive.md` 和相关索引规范。
- [x] 重新生成 Git 跟踪的 `docs/**` 清单，确认总数、保留数和归档数仍为 162/29/133。
- [x] 检查工作区并记录任务外并行改动，禁止纳入本次暂存区。
- [x] 读取 `archive/index.json` 最大批次号，为本轮选择下一个批次。
- [x] 对 5 个历史目录和 46 个 cheatsheet 候选路径运行归档 `plan`。
- [x] 审核 plan 中的目标路径、Git 状态和活动引用；未发现需要保留的新活动依赖。
- [x] 使用 batch 7/8 执行归档，不改写归档正文；batch 8 用于规避三对中文路径的稳定 ID 冲突。
- [x] 搜索活动源码、测试、配置、README、保留文档和活动任务中的旧路径，迁移必要引用。
- [x] 扫描保留 Markdown 的相对链接，修复唯一真实断链并确认 28 个保留 Markdown 均通过。
- [x] 运行归档工具 `check`，78 条索引记录通过。
- [x] 运行根目录 `pnpm qa` 和 `pnpm test:pwsh:all`；host 762 通过、Linux 759 通过，均 0 失败。
- [x] 检查 `git diff --summary` 的 rename 识别、`git diff --check` 和最终文件计数。
- [ ] 只暂存本任务相关文件，使用 Conventional Commits 中文提交信息提交。

## 回滚点

- 执行前：`plan` 不写文件，可直接调整候选清单。
- 执行后未提交：按本批索引反向移动并还原引用。
- 提交后：使用独立反向提交恢复，不重写已有 Git 历史。
