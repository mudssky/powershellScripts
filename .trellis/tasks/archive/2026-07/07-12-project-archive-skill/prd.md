# 项目冷归档技能与索引自动化

## Goal

把仓库冷归档流程沉淀为项目级 skill，并以机器可读配置替代人工维护的 Markdown 表格。归档事实只维护一份，agent 可以通过确定性脚本规划、执行和校验归档。

## Background

- 根 `archive/` 已是冷归档唯一目录，内部镜像原始仓库相对路径。
- `.trellis/spec/infra/repository-archive.md` 已定义 `git mv`、Git 跟踪、活动引用检查、质量工具排除和恢复规则。
- 当前 `archive/README.md` 人工维护 5 列表格，已包含两个批次的 8 个对象；本任务将其内容迁入 JSON 后删除该文件。
- 旧任务已将 `.vercel/project.json` 移至 `archive/.vercel/project.json`，证明现有目录合同可用。
- 项目级 skill 放在 `.agents/skills/`，主要内容使用中文。

## Requirements

### R1. 项目级归档 skill

- 新建 `.agents/skills/project-archive/`，入口为 `SKILL.md`。
- skill 说明候选审计、风险确认、镜像目标、活动引用检查、dry-run、执行、索引更新、验证和回滚流程。
- skill 必须复用项目归档规范和自带脚本，不复制一套易漂移的手工命令。
- skill 安装态自包含，不依赖 `.trellis/tasks/**` 或本机绝对路径。

### R2. 结构化归档索引

- 新增 `archive/index.json`，作为归档索引唯一真源。
- 配置保留现有字段语义：批次、原路径、归档路径、原因、替代入口或恢复说明。
- 每项具有稳定 ID，便于脚本精确选择、更新和恢复。
- 路径使用仓库相对 POSIX 形式；归档路径必须等于 `archive/<原路径>`。
- 迁移当前 `archive/README.md` 的全部索引项，不丢失信息；迁移完成后删除 README。

### R3. 确定性归档脚本

- 使用仅依赖 Python 标准库的脚本，支持 Windows、macOS 和 Linux。
- 至少支持 `check`、`plan` 和 `archive` 子命令。
- `check` 校验 schema、唯一性、镜像路径和源/目标状态。
- `plan` 输出候选归档的移动目标、引用风险和索引草案，不写文件。
- `archive` 默认拒绝隐式写入，必须显式确认执行；使用 `git mv`，不改写被归档文件正文，并在同一次操作中更新 JSON 索引。
- CLI stdout 保持稳定，错误写 stderr，并使用可测试的退出码。

### R4. 测试与质量门禁

- 为脚本补充标准库 `unittest`，覆盖成功、失败和边界场景。
- 覆盖无效 JSON、重复 ID/路径、非镜像目标、源目标冲突、dry-run、JSON 原子写入和 Git 命令失败。
- 运行 skill 结构审计、CLI help、单元测试、compileall 和根 `pnpm qa`。
- 本任务不修改 PowerShell 路径，不要求 `pnpm test:pwsh:all`。

## Acceptance Criteria

- [x] `.agents/skills/project-archive/SKILL.md` 能从候选审计走到归档、验证和回滚。
- [x] `archive/index.json` 完整表达当前 8 个归档对象，并成为唯一索引真源。
- [x] 原 README 的 8 条记录无损迁移到 JSON，且 `archive/README.md` 被删除。
- [x] `check` 能发现 schema、路径和仓库状态问题。
- [x] `plan` 不修改工作区；`archive` 只有显式执行时才调用 `git mv`，并同步更新 JSON。
- [x] 单元测试覆盖危险操作保护和主要错误分支。
- [x] skill 审计、脚本验证和 `pnpm qa` 全部通过。

## Out Of Scope

- 本任务不立即归档 `.promptx`、`.trae` 或其他新候选目录。
- 不修改现有质量工具对 `archive/**` 的排除合同。
- 不建立 WebUI、数据库或第三方依赖。
