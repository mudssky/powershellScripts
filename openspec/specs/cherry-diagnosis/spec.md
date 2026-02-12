## ADDED Requirements

### Requirement: Cherry 诊断分析
在执行 rebase 之前，系统 SHALL 使用 `git cherry <base> <branch>` 分析 feature 分支的 commit 重复情况。系统 SHALL 统计 unique（`+`）和 duplicate（`-`）commit 的数量，并据此自动选择最优同步策略。

#### Scenario: 全部 commit 已在 base 中（无独有 commit）
- **WHEN** `git cherry` 结果全部为 `-`（unique=0, dup>0）
- **THEN** 系统 SHALL 执行 `git reset --hard <base>` 直接对齐，跳过 rebase，并显示诊断信息 "检测到 N/N 个 commit 已在 base 中，直接对齐到 base"

#### Scenario: 大量重复 + 少量独有 commit
- **WHEN** `git cherry` 结果中 duplicate 占比超过 50%（dup/total > 0.5 且 unique > 0）
- **THEN** 系统 SHALL 执行 `git reset --hard <base>` 后逐个 `git cherry-pick` 那些 unique commit（`+` 标记的），并显示诊断信息 "检测到 dup/total 个重复 commit，将使用 reset + cherry-pick 策略"

#### Scenario: 无重复或少量重复 commit
- **WHEN** `git cherry` 结果中 duplicate 占比不超过 50%（dup/total ≤ 0.5）
- **THEN** 系统 SHALL 执行标准 rebase 流程（当前行为不变）

#### Scenario: Feature 分支无独有 commit 且不落后
- **WHEN** feature 分支既无独有 commit（unique=0）也不落后 base（behind=0）
- **THEN** 系统 SHALL 提示 "已是最新，无需同步"，不执行任何操作

### Requirement: Reset 操作安全确认
当 cherry 诊断决定使用 reset 策略时，系统 SHALL 在执行 `git reset --hard` 前显示诊断摘要，但不弹出确认框，直接执行。系统 SHALL 确保工作区 clean 检查已在前置步骤完成。

#### Scenario: Reset 前显示诊断信息
- **WHEN** 系统决定使用 reset 或 reset + cherry-pick 策略
- **THEN** 系统 SHALL 显示：策略类型、重复 commit 数、独有 commit 数（如有）、将要 cherry-pick 的 commit 列表（如有），然后直接执行

### Requirement: Cherry-pick 冲突处理
当 reset + cherry-pick 策略中 cherry-pick 产生冲突时，系统 SHALL 提供与 rebase 冲突相同的三选项处理流程。

#### Scenario: Cherry-pick 单个 commit 冲突
- **WHEN** 在 cherry-pick 某个 unique commit 时产生冲突
- **THEN** 系统 SHALL 列出冲突文件，并提供三个选项：(1) Claude 协助解决 (2) 用户手动解决后继续 (3) 中止（执行 `git cherry-pick --abort`）

#### Scenario: 批量模式下 cherry-pick 冲突
- **WHEN** `--all` 模式下某个分支的 cherry-pick 产生冲突
- **THEN** 系统 SHALL 执行 `git cherry-pick --abort`，然后执行 `git reset --hard` 恢复到 cherry 诊断前的 HEAD，记录为 "❌ 跳过（冲突）"，继续处理下一个分支
