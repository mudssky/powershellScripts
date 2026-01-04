## 🛠️ Part 1: Git Worktree 速查表 (Cheatsheet)

### 基础操作 (CRUD)

| 场景 | 命令 | 说明 |
| :--- | :--- | :--- |
| **新建 Worktree** (基于当前分支) | `git worktree add ../<目录名>` | 在上级目录创建新工作树，基于当前 HEAD |
| **新建 Worktree** (新建分支) | `git worktree add -b <分支名> ../<目录名>` | **最常用**。创建新分支并检出到新目录 |
| **新建 Worktree** (基于特定分支) | `git worktree add ../<目录名> <已有分支名>` | 基于已存在的特定分支创建目录 |
| **查看列表** | `git worktree list` | 显示所有工作树路径、关联的 commit 和分支 |
| **删除 Worktree** | `git worktree remove ../<目录名>` | 安全删除工作树（检查是否有未提交更改） |
| **强制删除** | `git worktree remove -f ../<目录名>` | 强制删除（包含未提交更改） |

### 维护与清理

| 场景 | 命令 | 说明 |
| :--- | :--- | :--- |
| **移动/重命名** | `git worktree move <旧路径> <新路径>` | 移动工作树目录（物理移动后需更新 git 索引） |
| **清理残留** | `git worktree prune` | 如果你手动 `rm -rf` 了目录，用此命令清理 git 记录 |
| **锁定** | `git worktree lock <路径>` | 防止工作树被自动 prune 或移动（用于外挂硬盘等） |
| **解锁** | `git worktree unlock <路径>` | 解除锁定 |

### 💡 最佳实践 Tips

1. **推荐目录结构 (Sibling 模式)**:
    不要在项目内部创建 worktree，这会弄乱 `.gitignore`。

    ```text
    /code
      /my-project-main   (主仓库)
      /my-project-feat1  (Worktree 1)
      /my-project-fix    (Worktree 2)
    ```

2. **依赖隔离**: 每个 Worktree 必须单独运行 `npm install` / `pip install`。
3. **分支互斥**: 同一个分支不能在两个 Worktree 中同时被检出。
4. **快速复制配置**: `cp .env ../my-project-feat1/`。

---

## 🚀 Part 2: 实战场景——迁移项目到 Monorepo

这是一个 Git Worktree 的**杀手级应用场景**。

**场景描述**：
你有一个独立的旧仓库 `OldApp`，需要将它迁移到一个新的 Monorepo 仓库 `CompanyMono` 中，路径为 `packages/old-app`。
**要求**：必须**保留 `OldApp` 的所有 Git 提交历史**。

**难点**：
直接合并会导致文件散落在 Monorepo 根目录。你需要先将 `OldApp` 的文件结构整体下沉（Move）到 `packages/old-app` 文件夹中，再合并。
**如果直接在 `OldApp` 主分支操作，会破坏现有开发环境。使用 Worktree 可以安全地在“隔离沙箱”中完成这个准备工作。**

### 操作步骤

#### 第一步：在旧仓库中准备“变形” (使用 Worktree)

我们不直接修改 `OldApp` 的 `main` 分支，而是开一个 Worktree 来做文件结构调整。

```bash
cd ~/projects/OldApp

# 1. 创建一个临时 worktree 用于迁移准备
# 分支名为 prepare-monorepo，目录在 ../OldApp-migration
git worktree add -b prepare-monorepo ../OldApp-migration

# 2. 进入临时工作树
cd ../OldApp-migration

# 3. 创建目标目录结构
mkdir -p packages/old-app

# 4. 将所有文件（除了 .git 和 packages）移动到新目录
# 注意：这里需要利用 extglob 或手动移动，确保除了 .git 以外都移进去
ls -A | grep -vE "^packages$|^\.git$" | xargs -I {} git mv {} packages/old-app/

# 5. 提交变更
git commit -m "chore: structure files for monorepo migration"

# 此时，在这个 Worktree 里，文件路径已经是 packages/old-app/src/... 了
# 但原来的 OldApp 主目录完全不受影响！
```

#### 第二步：在 Monorepo 中合并

现在回到你的 Monorepo 仓库，把刚才处理好的分支吸纳进来。

```bash
cd ~/projects/CompanyMono

# 1. 将旧仓库添加为远程仓库 (指向本地路径即可)
git remote add old-app-repo ~/projects/OldApp

# 2. 拉取数据
git fetch old-app-repo

# 3. 合并刚才在 Worktree 中准备的分支
# --allow-unrelated-histories 是关键，因为两个仓库历史不通
git merge old-app-repo/prepare-monorepo --allow-unrelated-histories -m "feat: migrate OldApp to monorepo"

# 4. 移除远程链接
git remote remove old-app-repo
```

#### 第三步：清理现场

```bash
cd ~/projects/OldApp
# 删除临时 Worktree
git worktree remove ../OldApp-migration
# (可选) 删除迁移分支
git branch -D prepare-monorepo
```

### 🤖 结合 Claude Code 的优势

在这个迁移过程中，Claude Code 可以在 **第一步（OldApp-migration 目录）** 发挥巨大作用：

1. **智能移动文件**：
    你可以对 Claude 说：*"请帮我把当前目录下除了 .git 以外的所有文件都移动到 `packages/old-app` 目录下，并更新相关的 import 路径（如果需要）"*。
    * Claude 能帮你处理复杂的 `git mv` 命令，甚至修正因移动文件导致的简单配置文件路径错误（如 `tsconfig.json` 或 `package.json` 中的路径）。

2. **解决冲突**：
    如果在合并到 Monorepo 时出现配置文件（如根目录的 `.gitignore` 或 `package.json`）冲突，你可以让 Claude 在 Monorepo 目录下帮你解决合并冲突。

### 总结

使用 `git worktree` 做迁移准备，最大的好处是**“无损”**。你可以在不影响旧项目正常 CI/CD 和同事开发的情况下，在一个平行宇宙（Worktree）里大刀阔斧地修改目录结构，直到确认无误后再合并进 Monorepo。
