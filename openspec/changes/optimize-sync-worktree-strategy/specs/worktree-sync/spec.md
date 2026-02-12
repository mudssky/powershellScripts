## MODIFIED Requirements

### Requirement: 状态概览显示
当用户调用 `/sync-worktree` 不带任何参数时，系统 SHALL 展示所有 worktree 的同步状态概览。概览 SHALL 包含每个 worktree 的分支名、路径、相对于 master 的领先/落后 commit 数、工作区是否干净、以及重复 commit 比例。主 worktree 的分支 SHALL 被标记为基准分支。

#### Scenario: 展示多个 worktree 状态（含重复 commit 预警）
- **WHEN** 用户调用 `/sync-worktree` 不带参数
- **THEN** 系统显示所有 worktree 的表格，包含 branch、path、ahead（领先 commit 数）、behind（落后 commit 数）、工作区状态（clean/dirty）、以及 Health 列（显示重复 commit 比例，如 "⚠ 29/30 重复"）

#### Scenario: 仅有主 worktree
- **WHEN** 用户调用 `/sync-worktree` 不带参数，且仅存在主 worktree（无 feature worktree）
- **THEN** 系统提示当前没有可同步的 feature worktree

#### Scenario: 无重复 commit 时不显示预警
- **WHEN** 用户调用 `/sync-worktree` 不带参数，且 feature 分支无重复 commit
- **THEN** Health 列显示 "✔"，不显示重复预警

### Requirement: 单分支 rebase 同步
用户 SHALL 能够指定一个 worktree 分支名，系统将根据 cherry 诊断结果自动选择最优策略（reset / reset+cherry-pick / rebase）同步该分支到基准分支。

#### Scenario: 成功同步到 master（标准 rebase）
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 cherry 诊断显示无重复或少量重复 commit
- **THEN** 系统执行标准 `git rebase master`，并报告成功结果和新 HEAD

#### Scenario: 成功同步到 master（reset + cherry-pick 策略）
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 cherry 诊断显示大量重复 commit
- **THEN** 系统执行 `git reset --hard master` + `git cherry-pick` 独有 commit，并报告成功结果和新 HEAD

#### Scenario: 成功同步到 master（直接 reset 策略）
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 cherry 诊断显示全部 commit 已在 master 中
- **THEN** 系统执行 `git reset --hard master` 直接对齐，并报告结果

#### Scenario: 分支已是最新
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 aifeat 已包含 master 的所有 commit
- **THEN** 系统提示 "aifeat 已是最新，无需同步"

#### Scenario: 指定分支不存在于 worktree
- **WHEN** 用户调用 `/sync-worktree nonexistent`
- **THEN** 系统报错，列出可用的 worktree 分支供用户选择

### Requirement: 批量同步
用户 SHALL 能够通过 `--all` 参数一次性将所有 feature worktree 同步到 master。每个分支 SHALL 独立执行 cherry 诊断并自动选择最优策略。

#### Scenario: 全部同步成功
- **WHEN** 用户调用 `/sync-worktree --all`，且所有 feature worktree 工作区干净且无冲突
- **THEN** 系统依次对每个 feature 分支执行 cherry 诊断 + 最优策略同步，并显示汇总结果

#### Scenario: 部分分支脏工作区
- **WHEN** 用户调用 `/sync-worktree --all`，且部分 worktree 有未提交改动
- **THEN** 系统跳过脏工作区的分支，同步其余分支，最终汇总中标注被跳过的分支及原因

#### Scenario: 部分分支冲突
- **WHEN** 用户调用 `/sync-worktree --all`，且部分 worktree 同步时产生冲突
- **THEN** 系统中止该分支的操作（abort rebase 或 abort cherry-pick + reset），跳过该分支继续处理剩余分支，最终汇总中标注冲突分支

### Requirement: 同步结果报告
每次同步完成后，系统 SHALL 显示操作结果汇总，包含使用的同步策略。

#### Scenario: 单分支同步报告
- **WHEN** 单分支同步成功完成
- **THEN** 系统显示：分支名、使用的策略（rebase / reset / reset+cherry-pick）、新 HEAD commit、同步的 commit 数量、是否需要 force push 到远程

#### Scenario: 批量同步汇总报告
- **WHEN** 批量同步完成
- **THEN** 系统显示汇总表格，列出每个分支的状态（✔ 成功 / ⚠ 跳过-脏工作区 / ❌ 跳过-冲突 / ℹ 已是最新）及使用的策略
