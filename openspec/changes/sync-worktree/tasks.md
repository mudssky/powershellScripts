## 1. Skill 基础结构

- [x] 1.1 创建 `.claude/skills/sync-worktree/SKILL.md` 文件，包含 frontmatter（name、description、metadata）和完整的 skill 指令
- [x] 1.2 编写参数解析逻辑说明：无参数（状态概览）、`<branch>`（单分支同步）、`--from <branch>`（自定义基准）、`--all`（批量同步）

## 2. 状态概览功能

- [x] 2.1 实现 worktree 发现：调用 `git worktree list --porcelain` 解析所有 worktree 的分支和路径
- [x] 2.2 实现基准分支检测：从主 worktree（bare=false 的第一个）提取分支名作为默认基准
- [x] 2.3 实现领先/落后计算：对每个 feature worktree 调用 `git rev-list --left-right --count <base>...<branch>`
- [x] 2.4 实现工作区状态检查：对每个 worktree 调用 `git -C <path> status --porcelain` 判断 clean/dirty
- [x] 2.5 实现状态表格输出格式：分支名、路径、ahead、behind、工作区状态，主 worktree 标记为 base

## 3. 单分支同步功能

- [x] 3.1 实现目标分支验证：检查指定分支名是否存在于 worktree 列表中，不存在则列出可用分支
- [x] 3.2 实现脏工作区拒绝：检查目标 worktree 工作区状态，脏则拒绝并提示 commit 或 stash
- [x] 3.3 实现已是最新检测：通过 `git rev-list --count <base>..<branch>` 和反向检查判断是否需要同步
- [x] 3.4 实现同步预览：显示将要同步的 commit 列表（`git log --oneline <merge-base>..<base>`）
- [x] 3.5 实现 rebase 执行：`git -C <worktree-path> rebase <base-branch>`
- [x] 3.6 实现成功报告：显示新 HEAD、同步的 commit 数、是否需要 force push

## 4. 冲突处理

- [x] 4.1 实现单分支冲突检测：识别 rebase 失败的退出码和冲突文件列表
- [x] 4.2 实现三选项交互：(1) Claude 协助解决 (2) 用户手动解决后 continue (3) abort
- [x] 4.3 实现批量模式冲突跳过：检测到冲突后自动 `git -C <path> rebase --abort`，记录跳过原因

## 5. 批量同步功能

- [x] 5.1 实现 `--all` 模式：遍历所有非主 worktree，逐个执行同步流程
- [x] 5.2 实现跳过逻辑：脏工作区 → 跳过；冲突 → abort + 跳过；已是最新 → 标记
- [x] 5.3 实现汇总报告：表格显示每个分支的最终状态（✔ 成功 / ⚠ 跳过-脏工作区 / ❌ 跳过-冲突 / ℹ 已是最新）

## 6. 验证

- [x] 6.1 在当前 worktree 环境下测试 `/sync-worktree`（无参数）状态概览输出
- [x] 6.2 测试 `/sync-worktree aifeat` 单分支同步流程
- [x] 6.3 验证脏工作区拒绝行为
