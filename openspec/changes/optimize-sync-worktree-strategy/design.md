## Context

当前 `sync-worktree` skill（v1.2）在 Step 4.6 直接执行 `git rebase`，不分析分支间的 commit 重复情况。当 feature 分支与 base 之间存在大量 patch-id 相同但 SHA 不同的 commit 时（由历史 cherry-pick 或非 ff-merge 导致），rebase 会逐个处理这些重复 commit，虽然 git 能自动跳过大部分，但遇到 rename/delete 等特殊冲突时处理极其困难。

实际案例：aifeat 有 30 个 commit，其中 29 个已在 master 中（patch-id 相同），rebase 时 29 个被跳过但唯一的独有 commit 遇到 rename/delete 冲突，最终手动 reset + cherry-pick 才解决。

## Goals / Non-Goals

**Goals:**
- 在 rebase 前自动诊断 commit 重复情况，选择最优同步策略
- 对于高重复场景，使用 reset + cherry-pick 替代 rebase，避免诡异冲突
- 在状态概览中提前展示重复 commit 预警，让用户了解分支健康度
- 保持无重复 commit 场景下的行为完全不变

**Non-Goals:**
- 不改变 `--merge` 模式的行为
- 不引入自动 stash 机制
- 不自动执行 `git push`
- 不处理 worktree 发现和参数解析逻辑（Step 1-2 不变）

## Decisions

### Decision 1: Cherry 诊断插入位置

在现有 Step 4.4（检查是否已是最新）之后、Step 4.5（同步预览）之前，新增 Step 4.4.1（cherry 诊断）。

**理由**：此时已确认分支存在、工作区 clean、基准已更新、且确实需要同步（behind > 0），是执行诊断的最佳时机。

### Decision 2: 策略选择阈值

使用 `dup/total > 50%` 作为切换到 reset + cherry-pick 策略的阈值。

| 条件 | 策略 |
|------|------|
| unique=0, dup>0 | `reset --hard <base>` |
| unique>0, dup/total > 50% | `reset --hard <base>` + `cherry-pick` unique commits |
| dup/total ≤ 50% | 标准 `rebase`（当前行为） |

**理由**：50% 是一个保守阈值。当超过一半的 commit 是重复的，rebase 的风险（诡异冲突）已经高于 reset + cherry-pick 的风险（cherry-pick 冲突更直观）。

**备选方案**：固定阈值（如 dup ≥ 3）。未采用，因为比例更能反映实际风险。

### Decision 3: 不弹策略选择框

cherry 诊断结果到最优策略是确定性映射，不需要用户选择。只在执行前打印一行诊断信息。

**理由**：减少交互摩擦。用户需要知道「发生了什么」，不需要做「选哪个」的决策。

### Decision 4: 批量模式下 reset + cherry-pick 的回滚

`--all` 模式下，如果某个分支的 cherry-pick 产生冲突：
1. `git cherry-pick --abort`
2. `git reset --hard <原始 HEAD>`（诊断前保存的 HEAD SHA）
3. 记录为 "❌ 跳过（冲突）"

**理由**：需要保存诊断前的 HEAD SHA，因为 reset --hard base 已经改变了 HEAD，abort cherry-pick 后需要恢复到原始状态。

### Decision 5: 状态概览的 Health 列

在 Step 3 的表格中新增 Health 列，对每个 feature 分支执行 `git cherry <base> <branch>` 并显示重复比例。

| 情况 | 显示 |
|------|------|
| 无重复 | ✔ |
| 有重复但占少数 | ℹ dup/total 重复 |
| 重复占多数 | ⚠ dup/total 重复 |

**理由**：提前预警，让用户在同步前就了解分支状态。

## Risks / Trade-offs

- **`git cherry` 性能**：对于 commit 数量极大的分支，`git cherry` 可能较慢。→ 缓解：仅在确认 behind > 0 后才执行，且 worktree 场景下 commit 数通常不会太大。
- **Reset 丢失 reflog 可读性**：`reset --hard` 比 rebase 在 reflog 中更难追踪。→ 缓解：诊断信息已打印策略和 commit 列表，且 reflog 仍然保留了 reset 前的 HEAD。
- **Cherry-pick 顺序**：`git cherry` 输出的 `+` commit 按原始顺序排列，cherry-pick 时保持该顺序。如果 commit 之间有依赖关系，顺序错误可能导致冲突。→ 缓解：按 `git cherry` 输出顺序（即原始 commit 顺序）执行 cherry-pick。
