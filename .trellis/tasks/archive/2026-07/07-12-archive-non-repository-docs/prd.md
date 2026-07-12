# 归档非本仓库文档

## Goal

收敛根目录 `docs/`，只在活动文档区保留与本仓库代码、配置、测试、安装、运维和工程约束直接相关的文档；将其余通用知识或纯历史资料迁入根 `archive/docs/` 镜像路径，并通过 `archive/index.json` 记录归档原因和替代说明。

## Background

- `docs/` 当前约 1.9 MB，包含安装说明、脚本索引、解决方案、通用 cheatsheet、旧 brainstorm/ideation/plan/superpowers/todo 等多类文档。
- 既有归档审计已认定 `docs/cheatsheet/**` 大部分属于 Git、语言、框架、数据库、终端等通用知识，但要求逐文件保留仓库专用例外。
- Trellis 已成为当前任务与规划真源，因此旧 `docs/brainstorms/**`、`docs/ideation/**`、`docs/plans/**`、`docs/superpowers/**` 和 `docs/todos/**` 统一作为历史资料冷归档。
- 归档必须使用 `project-archive` 工具迁入 `archive/docs/<原相对路径>`，同步更新 `archive/index.json`，不能删除正文或在移动时改写归档文件。
- 当前共有 162 个 Git 跟踪的 `docs/**` 文件。按最终分类，保留 29 个仓库相关文档，归档 133 个通用或历史文档。

## Requirements

- R1：保留直接描述本仓库安装、脚本入口、测试流程、实现方案、故障解决方案或当前工程约束的文档。
- R2：保留被源码、测试、配置、README、AI 索引或活动 Trellis 任务直接引用的文档，除非先迁移对应活动引用。
- R3：将与本仓库没有直接关系的通用知识文档归档到 `archive/docs/` 镜像路径。
- R4：逐文件审计 `docs/cheatsheet/**`，不能整目录无差别归档。
- R5：至少保留已确认的仓库相关例外：
  - `docs/cheatsheet/network/tailscale/index.md`，被测试直接读取并记录本仓 DERP/Tailscale 入口。
  - `docs/cheatsheet/vscode/remote/setup-ssh.md`，被 OpenSSH 脚本的用户提示引用。
  - `docs/cheatsheet/linux/docker/docker-bind-localhost.md`，包含本仓 `start-container.ps1` 行为。
  - `docs/cheatsheet/github/dependabot.md`，包含本仓 Dependabot/workspace 策略。
  - `docs/cheatsheet/vscode/remote/devcontainers.md`，指向本仓 Dev Container 模板。
  - `docs/cheatsheet/security/betterleaks-guide.md`，说明根 `.betterleaksignore`。
  - `docs/cheatsheet/pwsh/script-template.ps1`，被 `AI-INDEX.md` 标为仓库脚本模板入口。
  - 其余保留 cheatsheet 及证据见 `research/docs-classification.md` 的完整 16 文件白名单。
- R6：归档前生成文件级候选表，记录保留/归档结论、证据、活动引用、替代入口与风险。
- R7：不移动 `ai/docs/**`；本任务范围仅限根 `docs/**`。
- R8：不修改或提交本任务开始前已存在的并行改动。
- R9：将 `docs/brainstorms/**`、`docs/ideation/**`、`docs/plans/**`、`docs/superpowers/**` 作为已被 Trellis 替代的历史规划资料归档；活动引用需要迁移到对应的 `archive/docs/**` 镜像路径。
- R10：将 `docs/todos/**` 全部作为历史待办归档，不为 `002-ready-p2-pwsh-test-followups.md` 新建 Trellis 任务；后续如需 coverage 补强，从归档历史重新提出。
- R11：混合 cheatsheet 不拆分；只要被源码/测试引用、指向仓库文件、描述仓库实际配置或承担仓库用户操作入口，就整篇保留在活动 `docs/`。

## Acceptance Criteria

- [x] 每个 `docs/**` 文件都有可审计的保留或归档分类。
- [x] 活动文档区不再保留与仓库无直接关系的通用知识文档。
- [x] 所有源码、测试、配置和活动入口引用均指向仍存在的活动文档。
- [x] 归档内容保持原文，目标路径为 `archive/docs/<原相对路径>`。
- [x] `archive/index.json` 包含本批归档条目，归档一致性检查通过。
- [x] 根目录 `pnpm qa` 和 `pnpm test:pwsh:all` 通过。
- [x] Git diff 正确识别为 rename，不夹带 `AGENTS.md` 或其他任务的并行改动。
- [x] 归档范围与 `research/docs-classification.md` 一致：54 个历史规划/待办文件和 79 个通用 cheatsheet，共 133 个文件。

## Out Of Scope

- 不迁移到外部知识库，不删除文档正文。
- 不归档 `ai/docs/**` 或仓库其他目录。
- 不重写归档文档内容。
