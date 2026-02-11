---
name: sync-worktree
description: 在多个 git worktree 分支之间同步代码（rebase / merge）。支持状态概览、单分支同步、批量同步、自定义基准分支、合并回主分支。
license: MIT
metadata:
  author: mudssky
  version: "1.0"
---

在多个 git worktree 分支之间通过 rebase 同步代码，或将 feature 分支 merge 回主分支。

**输入**: `/sync-worktree` 后的参数决定运行模式：

| 用法 | 说明 |
|------|------|
| `/sync-worktree` | 状态概览：显示所有 worktree 的同步状态 |
| `/sync-worktree <branch>` | 拉代码：将指定分支 rebase 到 master |
| `/sync-worktree <branch> --from <base>` | 自定义基准：将指定分支 rebase 到 `<base>` |
| `/sync-worktree <branch> --merge` | 合并回主分支：将指定分支 merge 到 master |
| `/sync-worktree --all` | 批量同步：将所有 feature worktree rebase 到 master |

---

## Step 1: 发现 Worktree

执行以下命令发现所有 worktree：

```bash
git worktree list --porcelain
```

解析输出，构建 worktree 列表。每个 worktree 条目包含：
- `worktree <path>` — 文件系统路径
- `HEAD <sha>` — 当前 commit
- `branch refs/heads/<name>` — 分支名

列表中的**第一个** worktree 是**主 worktree**。提取其分支名作为**默认基准分支**（通常是 `master` 或 `main`）。

将所有 worktree 存储为列表：`{ path, branch, head }`。

---

## Step 2: 解析参数

从用户输入（ARGUMENTS 字符串）中判断模式：

1. **无参数** → 状态概览模式（跳转 Step 3）
2. **`--all`** → 批量同步模式（跳转 Step 6）
3. **`<branch>`** → 单分支同步模式
   - 检查是否同时提供了 `--from <base>`；如果有，使用该分支替代默认基准
   - 跳转 Step 4

---

## Step 3: 状态概览（无参数）

对每个 worktree 收集以下信息：

1. **相对于基准分支的领先/落后数**：对每个 feature worktree 执行：
   ```bash
   git rev-list --left-right --count <base>...<branch>
   ```
   输出格式：`<ahead>\t<behind>`（left = 基准领先数，right = 分支领先数）。
   - "ahead" = 该分支独有的 commit 数（基准没有的）
   - "behind" = 基准独有的 commit 数（需要同步的）

2. **工作区状态**：对每个 worktree 执行：
   ```bash
   git -C <worktree-path> status --porcelain
   ```
   输出为空 = clean；非空 = dirty。

以表格形式展示：

```
┌─ Worktree Status ───────────────────────────────────────────────┐
│                                                                 │
│  Branch       Path                                vs <base>     │
│  ──────       ────                                ─────────     │
│  master    ✦  /path/to/main                        (base)       │
│  aifeat       /path/to/aifeat-worktree             ↑1 ↓2 ✔     │
│  hotfix       /path/to/hotfix-worktree             ↑0 ↓3 ⚠ dirty│
│                                                                 │
│  ✦ = 当前所在 worktree                                           │
│  ↑ = 领先（自己独有的 commit）                                    │
│  ↓ = 落后（需要同步的 commit）                                    │
│  ✔ = clean  ⚠ = dirty                                           │
└─────────────────────────────────────────────────────────────────┘
```

如果没有 feature worktree（只有主 worktree），显示：
> 当前没有可同步的 feature worktree。使用 `git worktree add` 创建新的 worktree。

**状态概览模式到此结束。**

---

## Step 4: 单分支同步

### 4.1 验证目标分支

检查指定的分支名是否存在于 worktree 列表中。如果不存在，报错并列出所有可用的 worktree 分支供用户选择。

如果指定了 `--from <base>`，验证该基准分支在本地是否存在：
```bash
git rev-parse --verify <base>
```
如果不存在，报错提示。

### 4.2 检查工作区状态

```bash
git -C <worktree-path> status --porcelain
```

如果输出**非空**，**拒绝**同步：
> ❌ `<branch>` 工作区有未提交改动，请先 commit 或 stash 后重试。

**不得继续执行。** 不要提供自动 stash 的选项。

### 4.3 检查是否已是最新

检查基准分支是否有该分支没有的 commit：
```bash
git rev-list --count <branch>..<base>
```

如果计数为 **0**，说明该分支已包含基准的所有 commit：
> ℹ `<branch>` 已是最新，无需同步。

**到此结束。**

### 4.4 同步预览

展示将要应用的 commit：
```bash
git log --oneline <branch>..<base>
```

显示格式：
```
将 rebase <branch> onto <base>

落后 <N> 个 commit:
  <sha1> <message1>
  <sha2> <message2>
  ...
```

### 4.5 执行 Rebase

```bash
git -C <worktree-path> rebase <base>
```

**如果 rebase 成功** → 跳转 Step 5（成功报告）

**如果 rebase 失败（冲突）** → 跳转 Step 4.6（冲突处理）

### 4.6 冲突处理（单分支模式）

当 rebase 产生冲突时：

1. 列出冲突文件：
   ```bash
   git -C <worktree-path> diff --name-only --diff-filter=U
   ```

2. 使用 **AskUserQuestion** 向用户提供三个选项：

   | 选项 | 说明 |
   |------|------|
   | Claude 协助解决 | 读取冲突文件，分析冲突内容，提出解决方案 |
   | 手动解决后继续 | 用户自行解决冲突，之后告知 Claude 执行 `git -C <path> rebase --continue` |
   | 中止 rebase | 执行 `git -C <path> rebase --abort`，恢复到同步前状态 |

   **如果用户选择「Claude 协助解决」**：
   - 读取每个冲突文件
   - 分析冲突标记（`<<<<<<<`、`=======`、`>>>>>>>`）
   - 提出解决方案并应用编辑
   - 暂存已解决的文件：`git -C <path> add <file>`
   - 继续 rebase：`git -C <path> rebase --continue`
   - 如果出现更多冲突，重复以上流程

---

## Step 5: 成功报告（单分支模式）

rebase 成功后，获取信息并展示：

```bash
# 获取新 HEAD
git -C <worktree-path> rev-parse --short HEAD
```

```bash
# 检查是否存在远程跟踪分支，判断是否需要 force push
git -C <worktree-path> rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null
```

报告格式：
```
✔ <branch> 已同步到 <base>

  新 HEAD:     <short-sha> <message>
  同步 commit: <N> 个
  远程分支:    <upstream>（需要 force push）| 无远程跟踪分支
```

如果该分支有远程跟踪分支，提醒：
> ⚠ 该分支有远程跟踪分支，rebase 后需要 `git push --force-with-lease` 来更新远程。

---

## Step 6: 批量同步（`--all`）

### 6.1 枚举同步目标

从 worktree 列表（Step 1）中选取所有**非主 worktree**，作为同步目标。

如果没有 feature worktree：
> 当前没有可同步的 feature worktree。

### 6.2 逐个处理分支

对每个 feature worktree 执行单分支同步流程（Step 4.1–4.5），但有以下区别：

- **脏工作区** → 记录为 `⚠ 跳过（脏工作区）`，继续处理下一个分支
- **已是最新** → 记录为 `ℹ 已是最新`，继续处理下一个分支
- **rebase 冲突** → 执行 `git -C <path> rebase --abort`，记录为 `❌ 跳过（冲突）`，继续处理下一个分支
- **成功** → 记录为 `✔ 成功`，继续处理下一个分支

**不要因任何单个分支的失败而停止。** 始终处理所有分支。

### 6.3 汇总报告

所有分支处理完毕后，显示汇总表格：

```
┌─ Sync Summary ──────────────────────────────────────────────┐
│                                                             │
│  Branch       Status              Detail                    │
│  ──────       ──────              ──────                    │
│  aifeat       ✔ 成功              同步了 3 个 commit         │
│  hotfix       ⚠ 跳过              脏工作区                   │
│  experiment   ❌ 跳过              rebase 冲突               │
│  docs         ℹ 已是最新           —                         │
│                                                             │
│  结果: 1 成功 / 1 跳过(脏) / 1 跳过(冲突) / 1 已是最新       │
└─────────────────────────────────────────────────────────────┘
```

如果有因冲突被跳过的分支，补充提示：
> ⚠ 冲突分支可单独处理：`/sync-worktree <branch>` 后手动解决冲突。

---

## 安全护栏

- **禁止自动 stash**：工作区有未提交改动时，直接拒绝并告知用户先 commit 或 stash。
- **禁止执行 `git push`**：本 skill 仅做本地 rebase。如需 force push，只提醒用户，不代为执行。
- **禁止使用 `git rebase -i`**：交互式 rebase 需要终端输入，不受支持。
- **批量模式冲突必须 abort**：`--all` 模式下遇到冲突时，始终执行 `git rebase --abort` 并跳过。
- **始终验证分支存在性**：在执行任何操作前，确认目标分支存在于 worktree 列表中。
