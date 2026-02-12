---
name: sync-worktree
description: 在多个 git worktree 分支之间同步代码（rebase / merge）。支持状态概览、单分支同步、批量同步、自定义基准分支、合并回主分支。
license: MIT
metadata:
  author: mudssky
  version: "1.3"
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
3. **`<branch> --merge`** → 合并回主分支模式（跳转 Step 7）
4. **`<branch>`** → 单分支同步模式
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

3. **重复 commit 诊断（Health）**：对每个有领先 commit 的 feature worktree 执行：
   ```bash
   git cherry <base> <branch>
   ```
   统计输出中 `+`（unique）和 `-`（duplicate）的数量：
   - 无重复（dup=0）→ 显示 `✔`
   - 有重复但占少数（dup/total ≤ 50%）→ 显示 `ℹ dup/total 重复`
   - 重复占多数（dup/total > 50%）→ 显示 `⚠ dup/total 重复`
   - 无领先 commit（ahead=0）→ 不显示 Health

以表格形式展示：

```
┌─ Worktree Status ──────────────────────────────────────────────────────┐
│                                                                        │
│  Branch     Path                          vs <base>     Health         │
│  ──────     ────                          ─────────     ──────         │
│  master  ✦  /path/to/main                  (base)        —            │
│  aifeat     /path/to/aifeat-worktree       ↑1 ↓2 ✔      ✔            │
│  hotfix     /path/to/hotfix-worktree       ↑30 ↓46 ✔    ⚠ 29/30 重复 │
│  docs       /path/to/docs-worktree         ↑0 ↓3 ⚠ dirty             │
│                                                                        │
│  ✦ = 当前所在 worktree                                                  │
│  ↑ = 领先（自己独有的 commit）                                           │
│  ↓ = 落后（需要同步的 commit）                                           │
│  ✔ = clean  ⚠ = dirty                                                  │
│  Health: ✔ = 无重复  ℹ = 少量重复  ⚠ = 大量重复（建议同步）              │
└────────────────────────────────────────────────────────────────────────┘
```

如果没有 feature worktree（只有主 worktree），显示：
> 当前没有可同步的 feature worktree。使用 `git worktree add` 创建新的 worktree。

**到此结束。**

### 3.1 交互选择

展示状态表格后，根据 worktree 数量动态构建选项，使用 **AskUserQuestion** 让用户选择下一步操作。

选项生成规则：
- 对每个 feature worktree 生成两个选项：
  - `rebase <branch>`：将 `<branch>` rebase 到基准分支（拉代码）
  - `merge <branch>`：将 `<branch>` 合并回基准分支
- 如果有多个 feature worktree，额外添加：
  - `rebase --all`：批量 rebase 所有 feature 分支
- 最后添加：
  - `取消`：不执行任何操作

示例（有 aifeat 和 hotfix 两个 feature worktree 时）：

| 选项 | 说明 |
|------|------|
| rebase aifeat | 将 aifeat rebase 到 master（拉代码） |
| merge aifeat | 将 aifeat 合并回 master |
| rebase hotfix | 将 hotfix rebase 到 master（拉代码） |
| merge hotfix | 将 hotfix 合并回 master |
| rebase --all | 批量 rebase 所有 feature 分支到 master |
| 取消 | 不执行任何操作 |

用户选择后，跳转到对应的 Step 执行：
- `rebase <branch>` → Step 4（单分支同步）
- `merge <branch>` → Step 7（合并回主分支）
- `rebase --all` → Step 6（批量同步）
- `取消` → 结束

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

分别检查 **feature worktree** 和 **基准 worktree** 的工作区状态：

```bash
git -C <worktree-path> status --porcelain
git -C <base-worktree-path> status --porcelain
```

如果 feature worktree 输出**非空**，**拒绝**同步：
> ❌ `<branch>` 工作区有未提交改动，请先 commit 或 stash 后重试。

如果基准 worktree 输出**非空**，**拒绝**同步：
> ❌ 基准分支 `<base>` 工作区有未提交改动，无法更新基准分支。请先 commit 或 stash 后重试。

**不得继续执行。** 不要提供自动 stash 的选项。

### 4.3 更新基准分支

在执行 rebase 之前，先从远程拉取基准分支的最新代码，确保同步到远程最新状态。

首先检查基准分支是否有远程跟踪分支：
```bash
git -C <base-worktree-path> rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null
```

如果有远程跟踪分支，执行 pull：
```bash
git -C <base-worktree-path> pull --rebase
```

- **如果 pull 成功**：显示 `ℹ 已更新基准分支 <base> 到最新`，继续后续步骤。
- **如果 pull 失败**（冲突或网络问题）：显示错误信息，**中止同步**：
  > ❌ 更新基准分支 `<base>` 失败，请手动处理后重试。

如果没有远程跟踪分支，跳过此步骤（使用本地基准分支继续）。

### 4.4 检查是否已是最新

检查基准分支是否有该分支没有的 commit：
```bash
git rev-list --count <branch>..<base>
```

如果计数为 **0**，说明该分支已包含基准的所有 commit：
> ℹ `<branch>` 已是最新，无需同步。

**到此结束。**

### 4.5 Cherry 诊断与策略选择

在确认需要同步后（behind > 0），执行 cherry 诊断分析 commit 重复情况。

**4.5.1 保存当前 HEAD**

保存诊断前的 HEAD SHA，用于策略失败时回滚：
```bash
ORIGINAL_HEAD=$(git -C <worktree-path> rev-parse HEAD)
```

**4.5.2 执行 cherry 分析**

```bash
git cherry <base> <branch>
```

统计输出中 `+`（unique）和 `-`（duplicate）的数量：
- `total` = 总 commit 数（`+` 和 `-` 的总和）
- `unique` = `+` 的数量（feature 分支真正独有的 commit）
- `dup` = `-` 的数量（patch-id 已在 base 中的 commit）

**4.5.3 策略决策矩阵**

| 条件 | 策略 | 说明 |
|------|------|------|
| `unique=0, dup>0` | **reset** | 无独有改动，直接对齐到 base |
| `unique>0, dup/total > 50%` | **reset+cherry-pick** | 大量重复，reset 后 cherry-pick 独有 commit |
| `dup/total ≤ 50%`（含 `dup=0`） | **rebase** | 无重复或少量重复，标准 rebase |

**4.5.4 显示诊断信息**

根据策略显示不同的诊断信息（不弹选择框，直接执行）：

- **reset 策略**：
  > ℹ 检测到 `<dup>`/`<total>` 个 commit 已在 `<base>` 中（无独有改动），将直接对齐到 `<base>`

- **reset+cherry-pick 策略**：
  > ℹ 检测到 `<dup>`/`<total>` 个重复 commit，将使用 reset + cherry-pick 策略
  >
  > 独有 commit（`<unique>` 个）：
  >   `<sha1>` `<message1>`
  >   `<sha2>` `<message2>`

- **rebase 策略**：
  > 跳过诊断信息，直接进入 Step 4.6（同步预览 + Rebase）

### 4.6 执行同步（按策略分支）

根据 Step 4.5.3 的策略决策，执行对应的同步流程：

**策略 A：reset（无独有 commit）**

```bash
git -C <worktree-path> reset --hard <base>
```

执行后直接跳转 Step 5（成功报告），策略字段为 `reset`。

**策略 B：reset + cherry-pick（大量重复 + 少量独有）**

1. Reset 到 base：
   ```bash
   git -C <worktree-path> reset --hard <base>
   ```

2. 按 `git cherry` 输出顺序，逐个 cherry-pick unique commit（`+` 标记的）：
   ```bash
   git -C <worktree-path> cherry-pick <sha>
   ```

3. **如果所有 cherry-pick 成功** → 跳转 Step 5（成功报告），策略字段为 `reset+cherry-pick`

4. **如果某个 cherry-pick 产生冲突** → 跳转 Step 4.7a（cherry-pick 冲突处理）

**策略 C：rebase（标准路径）**

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

执行 rebase：
```bash
git -C <worktree-path> rebase <base>
```

- **如果 rebase 成功** → 跳转 Step 5（成功报告），策略字段为 `rebase`
- **如果 rebase 失败（冲突）** → 跳转 Step 4.7（rebase 冲突处理）

### 4.7 冲突处理（rebase 冲突）

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

### 4.7a 冲突处理（cherry-pick 冲突）

当 reset + cherry-pick 策略中 cherry-pick 产生冲突时：

1. 列出冲突文件：
   ```bash
   git -C <worktree-path> diff --name-only --diff-filter=U
   ```

2. 使用 **AskUserQuestion** 向用户提供三个选项：

   | 选项 | 说明 |
   |------|------|
   | Claude 协助解决 | 读取冲突文件，分析冲突内容，提出解决方案 |
   | 手动解决后继续 | 用户自行解决冲突，之后告知 Claude 执行 `git -C <path> cherry-pick --continue` |
   | 中止并回滚 | 执行 `git -C <path> cherry-pick --abort`，然后 `git -C <path> reset --hard <ORIGINAL_HEAD>` 恢复到诊断前状态 |

   **如果用户选择「Claude 协助解决」**：
   - 读取每个冲突文件
   - 分析冲突标记（`<<<<<<<`、`=======`、`>>>>>>>`）
   - 提出解决方案并应用编辑
   - 暂存已解决的文件：`git -C <path> add <file>`
   - 继续 cherry-pick：`git -C <path> cherry-pick --continue`
   - 继续处理剩余的 unique commit

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

  同步策略:    reset | reset+cherry-pick | rebase
  新 HEAD:     <short-sha> <message>
  同步 commit: <N> 个
  远程分支:    <upstream>（需要 force push）| 无远程跟踪分支
```

如果该分支有远程跟踪分支，提醒：
> ⚠ 该分支有远程跟踪分支，rebase 后需要 `git push --force-with-lease` 来更新远程。

### 5.1 询问是否合并回基准分支

展示成功报告后，使用 **AskUserQuestion** 询问用户是否要将该分支合并回基准分支：

| 选项 | 说明 |
|------|------|
| 合并回 `<base>` | 继续将 `<branch>` merge 到基准分支（跳转 Step 7.5） |
| 不合并 | 仅完成 rebase，到此结束 |

如果用户选择「合并回 `<base>`」，跳转 Step 7.5（合并预览），继续执行合并流程。此时无需重复 Step 7.1–7.4（验证、工作区检查、更新基准、同步检查），因为刚刚已经完成了这些步骤。

如果用户选择「不合并」，**到此结束。**

**注意**：当 Step 5 是从 Step 7（合并回主分支 → 先同步再合并）调用时，跳过此交互，直接继续 Step 7.5 的合并流程。

---

## Step 6: 批量同步（`--all`）

### 6.1 枚举同步目标

从 worktree 列表（Step 1）中选取所有**非主 worktree**，作为同步目标。

如果没有 feature worktree：
> 当前没有可同步的 feature worktree。

### 6.2 更新基准分支

在逐个处理 feature 分支之前，先更新基准分支（仅执行一次）。

1. 检查基准 worktree 工作区状态：
   ```bash
   git -C <base-worktree-path> status --porcelain
   ```
   如果有未提交改动，**中止整个批量同步**：
   > ❌ 基准分支 `<base>` 工作区有未提交改动，无法更新。请先 commit 或 stash 后重试。

2. 检查是否有远程跟踪分支并拉取：
   ```bash
   git -C <base-worktree-path> rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null
   ```
   如果有，执行：
   ```bash
   git -C <base-worktree-path> pull --rebase
   ```
   - 成功：显示 `ℹ 已更新基准分支 <base> 到最新`，继续。
   - 失败：**中止整个批量同步**，提示用户手动处理。

### 6.3 逐个处理分支

对每个 feature worktree 执行单分支同步流程（Step 4.1–4.6），但有以下区别：

- **脏工作区** → 记录为 `⚠ 跳过（脏工作区）`，继续处理下一个分支
- **已是最新** → 记录为 `ℹ 已是最新`，继续处理下一个分支
- **同步成功**（任何策略） → 记录为 `✔ 成功（<策略>）`，继续处理下一个分支
- **rebase 冲突** → 执行 `git -C <path> rebase --abort`，记录为 `❌ 跳过（冲突）`，继续处理下一个分支
- **cherry-pick 冲突**（reset+cherry-pick 策略） → 执行 `git -C <path> cherry-pick --abort`，然后 `git -C <path> reset --hard <ORIGINAL_HEAD>` 恢复到诊断前状态，记录为 `❌ 跳过（冲突）`，继续处理下一个分支

**不要因任何单个分支的失败而停止。** 始终处理所有分支。

**注意**：批量模式下跳过 Step 4.3（更新基准分支），因为已在 Step 6.2 统一更新过。每个分支独立执行 Step 4.5（cherry 诊断）选择最优策略。

### 6.4 汇总报告

所有分支处理完毕后，显示汇总表格：

```
┌─ Sync Summary ──────────────────────────────────────────────────────┐
│                                                                     │
│  Branch       Status              Strategy          Detail          │
│  ──────       ──────              ────────          ──────          │
│  aifeat       ✔ 成功              rebase            同步了 3 个 commit│
│  hotfix       ⚠ 跳过              —                 脏工作区          │
│  experiment   ❌ 跳过              reset+cherry-pick  冲突             │
│  docs         ℹ 已是最新           —                 —               │
│  staging      ✔ 成功              reset             直接对齐          │
│                                                                     │
│  结果: 2 成功 / 1 跳过(脏) / 1 跳过(冲突) / 1 已是最新               │
└─────────────────────────────────────────────────────────────────────┘
```

如果有因冲突被跳过的分支，补充提示：
> ⚠ 冲突分支可单独处理：`/sync-worktree <branch>` 后手动解决冲突。

---

## Step 7: 合并回主分支（`--merge`）

当用户使用 `/sync-worktree <branch> --merge` 时，将指定 feature 分支合并到主分支（master）。

### 7.1 验证目标分支

同 Step 4.1，检查指定的分支名是否存在于 worktree 列表中。

### 7.2 检查双方工作区状态

分别检查 **feature worktree** 和 **主 worktree** 的工作区状态：

```bash
git -C <feature-worktree-path> status --porcelain
git -C <main-worktree-path> status --porcelain
```

任一方有未提交改动，**拒绝**合并：
> ❌ `<branch>` 工作区有未提交改动，请先 commit 或 stash 后重试。

或：
> ❌ 主分支 `<base>` 工作区有未提交改动，请先 commit 或 stash 后重试。

### 7.3 更新基准分支

在合并之前，先从远程拉取基准分支的最新代码。

检查基准分支是否有远程跟踪分支：
```bash
git -C <main-worktree-path> rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null
```

如果有远程跟踪分支，执行：
```bash
git -C <main-worktree-path> pull --rebase
```

- 成功：显示 `ℹ 已更新基准分支 <base> 到最新`，继续。
- 失败：**中止合并**，提示用户手动处理。

如果没有远程跟踪分支，跳过此步骤。

### 7.4 检查是否需要先同步

检查 feature 分支是否落后于主分支：
```bash
git rev-list --count <branch>..<base>
```

如果计数 **> 0**，说明 feature 分支还没有包含主分支的最新 commit。**建议用户先同步**：
> ⚠ `<branch>` 落后 `<base>` N 个 commit，建议先执行 `/sync-worktree <branch>` 同步后再合并，以获得干净的 fast-forward merge。

使用 **AskUserQuestion** 让用户选择：

| 选项 | 说明 |
|------|------|
| 先同步再合并（推荐） | 先执行 rebase 同步，再 merge（产生 fast-forward） |
| 直接合并 | 跳过同步，直接 merge（可能产生 merge commit） |
| 取消 | 不执行任何操作 |

如果用户选择「先同步再合并」，先执行 Step 4 的完整流程，成功后继续 Step 7.5。

### 7.5 合并预览

展示将要合并到主分支的 commit：
```bash
git log --oneline <base>..<branch>
```

显示格式：
```
将 merge <branch> into <base>

包含 <N> 个 commit:
  <sha1> <message1>
  <sha2> <message2>
  ...
```

### 7.6 执行 Merge

在**主 worktree** 目录中执行 merge：
```bash
git -C <main-worktree-path> merge <branch>
```

如果 feature 分支已经 rebase 过，这通常是一个 **fast-forward merge**（不产生额外的 merge commit）。

**如果 merge 成功** → 跳转 Step 7.7（成功报告）

**如果 merge 失败（冲突）** → 类似 Step 4.7 的冲突处理流程，但操作目录改为主 worktree：
1. 列出冲突文件：`git -C <main-worktree-path> diff --name-only --diff-filter=U`
2. 提供三个选项：Claude 协助解决 / 手动解决后 `git -C <path> merge --continue` / 中止 `git -C <path> merge --abort`

### 7.7 成功报告（Merge）

```bash
git -C <main-worktree-path> rev-parse --short HEAD
git -C <main-worktree-path> log --oneline -1
```

报告格式：
```
✔ <branch> 已合并到 <base>

  新 HEAD:     <short-sha> <message>
  合并方式:    fast-forward | merge commit
  合并 commit: <N> 个
```

---

## 安全护栏

- **禁止自动 stash**：工作区有未提交改动时，直接拒绝并告知用户先 commit 或 stash。
- **自动更新基准分支**：在 rebase/merge 之前，自动对基准分支执行 `git pull --rebase`，确保同步到远程最新代码。仅当基准分支有远程跟踪分支且工作区 clean 时执行。pull 失败时中止操作。
- **禁止执行 `git push`**：本 skill 仅做本地 rebase/merge。如需 force push，只提醒用户，不代为执行。
- **禁止使用 `git rebase -i`**：交互式 rebase 需要终端输入，不受支持。
- **批量模式冲突必须 abort**：`--all` 模式下遇到冲突时，始终执行 abort（`git rebase --abort` 或 `git cherry-pick --abort` + `git reset --hard <ORIGINAL_HEAD>`）并跳过。
- **始终验证分支存在性**：在执行任何操作前，确认目标分支存在于 worktree 列表中。
