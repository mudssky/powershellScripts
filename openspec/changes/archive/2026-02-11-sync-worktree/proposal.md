## Why

在使用 git worktree 进行多分支并行开发时，feature 分支需要频繁从 master 拉取最新代码（rebase），同时偶尔也需要从其他 feature 分支同步。当前这个操作需要手动 `cd` 到对应 worktree 目录、检查工作区状态、执行 `git rebase`，流程繁琐且容易遗漏状态检查。需要一个 Claude Code Skill 来自动化这个流程，提供状态概览、安全检查和批量同步能力。

## What Changes

- 新增 Claude Code Skill `/sync-worktree`，支持以下功能：
  - 无参数调用时展示所有 worktree 的同步状态概览（领先/落后 commit 数、工作区是否干净）
  - 指定分支同步：默认 rebase onto master，支持 `--from <branch>` 指定其他基准分支
  - 批量同步 `--all`：将所有 feature worktree rebase onto master，冲突分支跳过并继续
  - 安全护栏：脏工作区直接拒绝同步，要求用户先 commit 或 stash
  - 冲突处理：单分支模式下协助用户解决或 abort；批量模式下自动 abort 并跳过

## Capabilities

### New Capabilities

- `worktree-sync`: 提供 git worktree 间的代码同步能力，包括状态概览、单分支/批量 rebase 同步、安全检查和冲突处理

### Modified Capabilities

（无已有 capability 需要修改）

## Impact

- 新增文件：`.claude/skills/sync-worktree/SKILL.md`
- 依赖：仅依赖 `git` CLI（worktree、rebase、log、rev-list 等子命令）
- 不影响现有 `bin/`、`scripts/`、`psutils/` 等模块
- 不引入新的外部依赖
