## Context

项目使用 git worktree 进行多分支并行开发（如 `master` + `aifeat`），worktree 分布在磁盘不同目录。当前同步操作需要手动 `cd` 到目标 worktree 目录执行 `git rebase`，缺乏统一的状态视图和安全检查机制。

该 command 以 Claude Code Skill（SKILL.md）形式实现，由 Claude Code 解释执行，不生成独立脚本。Skill 内部通过调用 `git` CLI 完成所有操作。

## Goals / Non-Goals

**Goals:**

- 提供所有 worktree 的同步状态一览（领先/落后 commit 数、工作区干净与否）
- 一条命令完成 rebase 同步，无需手动 cd 到 worktree 目录
- 支持批量同步所有 feature worktree
- 脏工作区安全拒绝，避免误操作
- 冲突场景提供清晰的处理路径

**Non-Goals:**

- 不实现 merge 策略（仅 rebase）
- 不实现 cherry-pick / 文件级同步
- 不管理 worktree 的创建与删除（已有 `zcf:git-worktree` skill）
- 不处理远程仓库的 push/pull（同步仅在本地分支间进行）
- 不自动 stash 脏工作区（直接拒绝，由用户决定如何处理）

## Decisions

### 1. 同步策略：仅支持 rebase

**选择**: 仅提供 rebase，不支持 merge。

**理由**: 用户明确偏好 rebase 以保持线性历史。feature 分支最终需要合回 master，rebase 产生的线性历史比 merge commit 更干净。单一策略也降低了 skill 的复杂度。

**替代方案**: 支持 `--strategy merge|rebase` 参数 → 增加复杂度但灵活性有限，用户已明确不需要 merge。

### 2. 脏工作区：拒绝而非自动 stash

**选择**: 检测到未提交改动时直接拒绝同步，提示用户先 commit 或 stash。

**理由**: 自动 stash → rebase → stash pop 链路中任一环节失败（尤其 stash pop 冲突）会使状态难以恢复。拒绝策略最安全，用户对自己的工作区状态有完全控制权。

**替代方案**: 自动 stash → 方便但风险高；询问用户 → 多一步交互但 skill 上下文中可用 AskUserQuestion。

### 3. 批量模式冲突处理：跳过并继续

**选择**: `--all` 模式下，某个分支 rebase 冲突时自动 `git rebase --abort`，跳过该分支继续处理剩余分支，最后汇总报告。

**理由**: 批量操作的目的是提效，逐个停下来解决冲突会破坏批量的意义。跳过 + 汇报让用户可以事后逐个处理冲突分支。

### 4. 实现形态：Claude Code SKILL.md

**选择**: 作为 `.claude/skills/sync-worktree/SKILL.md` 实现，由 Claude Code 解释执行。

**理由**: Skill 可以利用 Claude 的上下文感知能力（如冲突时协助分析），比纯 shell 脚本更灵活。且项目已有大量 skill 先例。

**替代方案**: PowerShell 脚本 → 可独立运行但失去 AI 辅助能力；两者兼有 → 维护成本翻倍。

### 5. 基准分支默认值检测

**选择**: 默认基准为 `master`，但通过 `git worktree list` 检测主 worktree 对应的分支作为实际默认值。支持 `--from <branch>` 覆盖。

**理由**: 大部分项目主分支是 `master` 或 `main`，从主 worktree 检测可以兼容两种命名。`--from` 参数覆盖默认值以支持 feature-to-feature 同步。

## Risks / Trade-offs

- **Rebase 改写历史** → 如果 feature 分支已推送到远程，rebase 后需要 force push。Skill 在结果报告中提醒用户这一点。
- **`--all` 跳过冲突分支可能被忽略** → 最终汇总报告中用醒目标记列出所有跳过的分支，确保用户注意到。
- **`git -C <path>` 依赖** → 要求 git 版本 >= 1.8.5（2013 年发布），几乎所有现代系统都满足，风险极低。
