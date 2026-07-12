# 实施计划

## 执行清单

- [x] 在 `.trellis/spec/infra/repository-archive.md` 增加 monorepo package 归档资格、退出清单和恢复要求。
- [x] 从 `CLAUDE.md`、`powershellScripts.code-workspace` 和 `docs/scripts-index.md` 清理活动引用。
- [x] 使用 pnpm 更新 lockfile，仅移除 `projects/clis/json-diff-tool` importer、其无共享依赖和相关 optional 状态。
- [x] 以 Batch 10 重新运行三个候选的 `plan`，确认目标路径、Git 跟踪状态和活动引用。
- [x] 用与 `plan` 完全相同的参数执行 `archive --execute`。
- [x] 检查 `archive/index.json` 新增三个 Batch 10 条目，且保留并行任务的 Batch 9 改动。
- [x] 检查 Git rename，确认归档文件正文未在移动中改写。
- [x] 运行完整验证：`project-archive check`、workspace/引用检查、`pnpm qa` 和 `pnpm test:pwsh:all` 均通过。
- [ ] 仅暂存本任务文件，按 `chore(archive): 归档 JSON 对比工具` 提交。

## 归档命令

```bash
python3 .agents/skills/project-archive/scripts/archive_project.py \
  --repo-root "$(git rev-parse --show-toplevel)" \
  plan \
  projects/clis/json-diff-tool \
  scripts/pwsh/misc/Compare-JsonFiles.ps1 \
  .trellis/spec/json-diff-tool \
  --batch 10 \
  --reason "JSON 对比工具已停止使用且无活动依赖" \
  --replacement-note "功能已停用，仅供历史参考"
```

获得用户对本计划的最终批准后，将 `plan` 替换为 `archive` 并追加 `--execute`。

## 验证命令

```bash
python3 .agents/skills/project-archive/scripts/archive_project.py \
  --repo-root "$(git rev-parse --show-toplevel)" check
pnpm list -r --depth -1
rg -n --hidden --glob '!archive/**' --glob '!.git/**' \
  'json-diff-tool|Compare-JsonFiles'
pnpm qa
pnpm test:pwsh:all
git status --short
git diff --stat
git diff --summary
```

## 风险文件

- `archive/index.json` 当前已有其他任务的未提交修改，执行时必须在现有内容上追加，不得回退或重建该文件。
- `pnpm-lock.yaml` 是共享工作区文件，更新后必须审查 diff，避免吸收无关依赖刷新。
- 当前 `psutils/**`、`.trellis/spec/psutils/**` 和 `.trellis/tasks/07-12-psutils-docs-examples/**` 存在并行改动，不得修改、暂存或提交。
