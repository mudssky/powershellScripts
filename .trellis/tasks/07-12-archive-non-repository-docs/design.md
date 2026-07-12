# 技术设计

## 边界

本次只处理 Git 跟踪的根 `docs/**`。活动文档保留原路径；通用知识和历史规划迁入 `archive/docs/<原相对路径>`。`ai/docs/**`、未跟踪文件和其他仓库目录不在范围内。

## 分类模型

1. 历史规划目录按目录整体归档。
2. cheatsheet 使用保留白名单；白名单之外的文件按不跨越白名单的最大目录子树归档。
3. 非 cheatsheet 文档默认保留，因为它们均承担仓库安装、测试、脚本索引、问题复盘或操作说明职责。
4. 混合文档只要承担仓库职责就整篇保留，不拆分正文。

精确分类以 `research/docs-classification.md` 为真源。

## 归档与索引

- 使用 `project-archive/scripts/archive_project.py` 对每个候选路径先运行 `plan`，确认镜像目标、Git 跟踪状态和活动引用。
- 所有对象使用同一新批次号；批次号取 `archive/index.json` 当前最大值加一。
- 历史规划的替代说明指向 `.trellis/tasks/` 与 `.trellis/spec/`。
- 通用 cheatsheet 使用“仅供历史参考”的 replacement note。
- 执行阶段不改写归档文件正文。

## 引用处理

- 只修复活动源码、测试、配置、README、保留文档和活动 Trellis 任务中的断链。
- 指向历史规划正文但仍有保留价值的链接改为 `archive/docs/**`。
- Trellis 已归档任务中的历史路径不作为本轮必须修改的活动引用。
- 对保留 Markdown 运行相对链接扫描，确保没有链接到消失的 `docs/**` 路径。

## 回滚

按 `archive/index.json` 本批条目反向 `git mv` 到原路径，删除本批索引条目，并还原活动引用修改。随后重新运行归档检查和 `pnpm qa`。

## 并行改动隔离

任务开始前已存在 `AGENTS.md` 修改和其他 Trellis 任务目录。暂存与提交时只包含本任务、`docs/**`、`archive/docs/**`、必要活动引用及 `archive/index.json`。
