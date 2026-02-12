## Why

当 feature 分支与 master 之间存在大量 patch-id 相同但 SHA 不同的重复 commit 时（通常由 cherry-pick 或非 ff-merge 导致），当前 skill 仍然执行标准 rebase，容易遇到 rename/delete 等诡异冲突，处理极其繁琐。需要在 rebase 前增加 cherry 诊断，自动选择最优同步策略（reset/cherry-pick/rebase），并在状态概览中提前预警。

## What Changes

- 新增 cherry 诊断步骤：在 rebase 前执行 `git cherry` 分析重复 commit 比例，自动选择最优策略
- 新增 reset + cherry-pick 同步策略：当重复 commit 占多数时，用 `reset --hard` + `cherry-pick` 替代 rebase
- 状态概览增强：显示每个 feature 分支的重复 commit 比例，提前预警分支漂移
- 批量同步适配：`--all` 模式下同样应用 cherry 诊断和策略自动选择

## Capabilities

### New Capabilities
- `cherry-diagnosis`: cherry 诊断与智能同步策略选择，包括 reset + cherry-pick 路径

### Modified Capabilities
- `worktree-sync`: 状态概览增加重复 commit 预警列；单分支/批量同步流程集成 cherry 诊断

## Impact

- 修改文件：`.claude/skills/sync-worktree/SKILL.md`
- 修改 spec：`openspec/specs/worktree-sync/spec.md`
- 无 API 或依赖变更
- 向后兼容：无重复 commit 时行为与当前完全一致
