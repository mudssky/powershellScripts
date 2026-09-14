---
name: trellis-push
description: "一键收尾：批量提交当前任务工作代码（Phase 3.4）、归档任务、记录 journal 并 push 远端，含 rebase 冲突与哈希修正处理。Use when 用户说 提交、push、走 finish 流程、一键提交推送、收尾 等要求完成提交并推送远端的场景。"
---

# Trellis Push（一键提交收尾）

把「Phase 3.4 提交 → finish-work（归档 + journal）→ push」压成一次顺序执行。代码提交在归档之前，push 在最后。

## Step 1: 勘察状态

```bash
python3 ./.trellis/scripts/get_context.py --mode record
git status --porcelain
git diff --check
```

- `.trellis/tasks/`、`.trellis/workspace/` 下的脏文件是归档/journal 脚本的自动提交范围，此时不要手动暂存。
- 其余脏文件按「是否属于当前任务」分流：属于本任务 → Step 2 一起提交；无关（其他窗口的并行工作）→ 原样保留并在汇报中说明；无法判断 → 问用户一次。
- 与远端有并行会话时，准备好处理 push 被拒（见 Step 5）。

## Step 2: 提交工作代码（Phase 3.4）

```bash
git add <本任务相关文件>
git commit -m "<type>(<scope>): <中文主题>"
```

- 遵循 Conventional Commits：`feat/fix/refactor/style/docs/test/chore + scope`，subject 中文。
- 提交信息正文列出关键变更点；一次任务一个批量提交即可，不与归档/journal 混在一起。

## Step 3: 归档任务

```bash
python3 ./.trellis/scripts/task.py archive <task-slug>
```

脚本自动产生 `chore(task): archive ...` 提交。若无活跃任务且用户未指定清理，跳过。

## Step 4: 记录 journal

```bash
python3 ./.trellis/scripts/add_session.py \
  --title "会话标题" \
  --commit "<Step 2 的工作提交哈希>" \
  --summary "简要总结"
```

- `--commit` 只写工作提交哈希，不含归档/journal 自动提交。
- 脚本自动产生 `chore: record journal` 提交。

## Step 5: push

```bash
git push origin master
```

### push 被拒（远端有新提交）

1. `git pull --rebase origin master`
2. 若有冲突：**语义合并，保留双方意图**，禁止无脑 `--ours/--theirs`。两边改到同一函数时，先读远端版本的实现再合并。
3. 代码冲突解决后必须重跑回归（对应包测试或根 `pnpm qa`）再继续。
4. `git add <resolved>` + `GIT_EDITOR=true git rebase --continue`，逐个回放。

### rebase 改写哈希后的修正（易漏）

- 回放后工作提交的哈希会变：用 `git log --oneline` 取新哈希，更新 journal 提交里的 `--commit` 引用（`.trellis/workspace/<user>/journal-*.md`），`git add` 后继续 rebase。
- `.trellis/workspace/<user>/index.md` 的会话序号冲突：与远端会话**顺延并存**（远端 69 则本会话 70），两边的 Session History 行都保留。

## 失败兜底

- rebase 想放弃：`git rebase --abort` 回到 pull 前状态（本地提交不丢）。
- journal 冲突只涉及 `.trellis/workspace/`：按双方条目并存解决，不影响代码。
- push 前本地工作树必须干净（`git status --porcelain` 为空），否则先完成 Step 2。
