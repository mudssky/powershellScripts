# 仓库冷归档批次

## Goal

创建根级镜像冷归档结构，迁移用户已批准的失效或历史内容，在保留 Git 跟踪、搜索和历史追溯能力的同时，让归档内容退出默认 workspace、构建、测试、格式化、lint 和发布流程。

## Background

- 父任务已决定不拆分新仓库，历史内容继续保留在当前仓库中。
- 冷归档统一使用根级 `archive/`，目标路径镜像原始相对路径。
- 已批准对象合计 20 个文件，当前磁盘占用约 92 KiB；本任务的价值是收敛生命周期边界，而不是显著缩小仓库体积。
- 已批准对象没有活动代码入口。现行文档中只有根 `README.md` 的目录树仍列出根 `deprecated/`；旧 Trellis 任务中的路径属于历史记录，不应追改。
- `scripts/pwsh/filesystem/renameLegal.ps1` 是 `ipynb/renameLegal.ipynb` 的有效替代入口；`macos/hammerspoon/` 是旧合盖轮询守卫的替代入口。

## Requirements

- R1：只迁移父任务 `archive-candidates.md` 中状态为“已批准归档”的对象：
  - `deprecated/**`
  - `profile/deprecated/**`
  - `macos/archive/**`
  - `config/frontend/deprecated/**`
  - `config/vscode/back/**`
  - `config/software/pixpin/deprecated/**`
  - `.vercel/project.json`
  - `ipynb/renameLegal.ipynb`
- R2：目标路径使用 `archive/<原始相对路径>`，迁移使用 `git mv`，不改写归档文件内容。
- R3：新增 `archive/README.md`，按批准对象记录批准批次、原路径、归档路径、归档原因、替代入口或恢复说明。
- R4：同步现行引用与目录说明；历史任务、历史设计和归档记录中的旧路径保持原样。
- R5：归档内容继续由 Git 跟踪并可被普通搜索发现，不通过 `.gitignore` 隐藏。
- R6：默认 workspace、构建、测试、格式化、lint 和发布流程不处理 `archive/**`；Git 安全扫描仍覆盖归档内容。
- R7：PowerShell 格式器的 Git 变更模式和递归模式都必须排除归档路径，并为排除行为补充自动化测试。
- R8：本轮不迁移 `docs/cheatsheet/**`、`ai/docs/**`、`linux/wsl2/deprecated/**` 或其他未批准对象。

## Acceptance Criteria

- [x] AC1：R1 中 8 个批准对象全部位于对应镜像归档路径，原路径不存在；未批准对象保持原位。
- [x] AC2：`archive/README.md` 能从每个批准对象追溯原路径、批准批次、原因和替代入口或恢复价值。
- [x] AC3：根 `README.md` 不再把根 `deprecated/` 描述为活动目录，现行文档和代码不存在指向已移动路径的活动引用。
- [x] AC4：`pnpm-workspace.yaml` 与 Turbo 任务图不包含 `archive/**`，项目构建、测试和发布入口不把归档内容当作活动资产。
- [x] AC5：Biome、rumdl、Ruff、notebook 清理、lint-staged 和 PowerShell 格式器的默认入口均排除 `archive/**`；安全扫描保持启用。
- [x] AC6：PowerShell 格式器自动化测试同时证明普通路径仍被发现、`archive/**` 在 Git 变更和递归扫描中均被跳过。
- [x] AC7：`pnpm qa` 通过；由于改动涉及 PowerShell 格式器和测试，`pnpm test:pwsh:all` 通过。
- [x] AC8：抽查至少一个移动文件可通过 `git log --follow -- <归档路径>` 追溯移动前历史。

## Out Of Scope

- 不删除归档内容，不把正文迁往外部知识库，也不重写历史提交。
- 不迁移 `docs/cheatsheet/**`、`ai/docs/**` 或第三批待确认目录。
- 不处理 `linux/wsl2/deprecated/**`；其活动入口依赖尚未收敛。
- 不为归档脚本修复旧缺陷、补充兼容 shim 或恢复可执行支持。
