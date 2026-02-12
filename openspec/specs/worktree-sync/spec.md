## ADDED Requirements

### Requirement: 状态概览显示
当用户调用 `/sync-worktree` 不带任何参数时，系统 SHALL 展示所有 worktree 的同步状态概览。概览 SHALL 包含每个 worktree 的分支名、路径、相对于 master 的领先/落后 commit 数、工作区是否干净、以及重复 commit 比例（Health 列）。主 worktree 的分支 SHALL 被标记为基准分支。

#### Scenario: 展示多个 worktree 状态（含重复 commit 预警）
- **WHEN** 用户调用 `/sync-worktree` 不带参数
- **THEN** 系统显示所有 worktree 的表格，包含 branch、path、ahead（领先 commit 数）、behind（落后 commit 数）、工作区状态（clean/dirty）、以及 Health 列（显示重复 commit 比例，如 "⚠ 29/30 重复"）

#### Scenario: 仅有主 worktree
- **WHEN** 用户调用 `/sync-worktree` 不带参数，且仅存在主 worktree（无 feature worktree）
- **THEN** 系统提示当前没有可同步的 feature worktree

#### Scenario: 无重复 commit 时不显示预警
- **WHEN** 用户调用 `/sync-worktree` 不带参数，且 feature 分支无重复 commit
- **THEN** Health 列显示 "✔"，不显示重复预警

### Requirement: 单分支智能同步
用户 SHALL 能够指定一个 worktree 分支名，系统将根据 cherry 诊断结果自动选择最优策略（reset / reset+cherry-pick / rebase）同步该分支到基准分支（默认 master）。

#### Scenario: 成功同步到 master（标准 rebase）
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 cherry 诊断显示无重复或少量重复 commit
- **THEN** 系统执行标准 `git rebase master`，并报告成功结果和新 HEAD

#### Scenario: 成功同步到 master（reset + cherry-pick 策略）
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 cherry 诊断显示大量重复 commit（dup/total > 50%）
- **THEN** 系统执行 `git reset --hard master` + `git cherry-pick` 独有 commit，并报告成功结果和新 HEAD

#### Scenario: 成功同步到 master（直接 reset 策略）
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 cherry 诊断显示全部 commit 已在 master 中（unique=0）
- **THEN** 系统执行 `git reset --hard master` 直接对齐，并报告结果

#### Scenario: 分支已是最新
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 aifeat 已包含 master 的所有 commit
- **THEN** 系统提示 "aifeat 已是最新，无需同步"

#### Scenario: 指定分支不存在于 worktree
- **WHEN** 用户调用 `/sync-worktree nonexistent`
- **THEN** 系统报错，列出可用的 worktree 分支供用户选择

### Requirement: 自定义基准分支
用户 SHALL 能够通过 `--from <branch>` 参数指定任意本地分支作为同步基准，覆盖默认的 master。

#### Scenario: Feature-to-feature 同步
- **WHEN** 用户调用 `/sync-worktree aifeat --from hotfix`
- **THEN** 系统对 aifeat 执行 cherry 诊断并选择最优策略同步到 hotfix

#### Scenario: 指定的基准分支不存在
- **WHEN** 用户调用 `/sync-worktree aifeat --from nonexistent`
- **THEN** 系统报错，提示基准分支不存在

### Requirement: 脏工作区拒绝
当目标 worktree 存在未提交的改动（包括 staged 和 unstaged）时，系统 SHALL 拒绝执行同步，并提示用户先 commit 或 stash。

#### Scenario: 工作区有未提交改动
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 aifeat worktree 有未提交改动
- **THEN** 系统拒绝同步，提示 "aifeat 工作区有未提交改动，请先 commit 或 stash 后重试"

#### Scenario: 工作区干净
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 aifeat worktree 工作区干净
- **THEN** 系统正常执行同步流程

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
- **THEN** 系统中止该分支的操作（abort rebase 或 abort cherry-pick + reset 到原始 HEAD），跳过该分支继续处理剩余分支，最终汇总中标注冲突分支

### Requirement: 单分支冲突处理
当单分支模式下同步产生冲突时（rebase 冲突或 cherry-pick 冲突），系统 SHALL 提供三个选项让用户选择。

#### Scenario: Rebase 冲突
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 rebase 过程中产生冲突
- **THEN** 系统列出冲突文件，并提供三个选项：(1) Claude 协助解决冲突 (2) 用户手动解决后继续 (3) 中止 rebase（git rebase --abort）

#### Scenario: Cherry-pick 冲突
- **WHEN** 用户调用 `/sync-worktree aifeat`，且 reset+cherry-pick 策略中 cherry-pick 产生冲突
- **THEN** 系统列出冲突文件，并提供三个选项：(1) Claude 协助解决冲突 (2) 用户手动解决后继续 (3) 中止并回滚（git cherry-pick --abort + git reset --hard 到原始 HEAD）

### Requirement: Cherry 诊断分析
在执行同步之前，系统 SHALL 使用 `git cherry <base> <branch>` 分析 feature 分支的 commit 重复情况，统计 unique（`+`）和 duplicate（`-`）commit 的数量，并据此自动选择最优同步策略。

#### Scenario: 全部 commit 已在 base 中
- **WHEN** `git cherry` 结果全部为 `-`（unique=0, dup>0）
- **THEN** 系统执行 `git reset --hard <base>` 直接对齐，并显示诊断信息

#### Scenario: 大量重复 + 少量独有 commit
- **WHEN** `git cherry` 结果中 duplicate 占比超过 50%（dup/total > 0.5 且 unique > 0）
- **THEN** 系统执行 `git reset --hard <base>` 后逐个 `git cherry-pick` unique commit，并显示诊断信息

#### Scenario: 无重复或少量重复 commit
- **WHEN** `git cherry` 结果中 duplicate 占比不超过 50%
- **THEN** 系统执行标准 rebase 流程

### Requirement: 同步结果报告
每次同步完成后，系统 SHALL 显示操作结果汇总，包含使用的同步策略。

#### Scenario: 单分支同步报告
- **WHEN** 单分支同步成功完成
- **THEN** 系统显示：分支名、使用的策略（rebase / reset / reset+cherry-pick）、新 HEAD commit、同步的 commit 数量、是否需要 force push 到远程

#### Scenario: 批量同步汇总报告
- **WHEN** 批量同步完成
- **THEN** 系统显示汇总表格，列出每个分支的状态（✔ 成功 / ⚠ 跳过-脏工作区 / ❌ 跳过-冲突 / ℹ 已是最新）及使用的策略
