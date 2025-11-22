Git 的最佳实践（Best Practices）旨在确保代码库的整洁、可维护性，并减少团队协作中的冲突。以下是整理好的 Git 使用最佳实践指南，分为 **提交习惯**、**分支管理**、**信息规范** 和 **安全与配置** 四个维度。

---

### 1. 提交习惯 (Commit Habits)

**原则：原子性提交 (Atomic Commits)**
每个提交（Commit）应该只做“一件事”。这使得回滚（Revert）和代码审查（Review）变得容易。

* **✅ 推荐：**
  * 频繁提交：不要等到一天结束才提交一次。
  * 逻辑独立：修复 Bug A 和开发 Feature B 应该是两个不同的提交。
  * 编译通过：确保每次提交的代码都是可运行的，不要提交破坏构建的代码。
* **❌ 避免：**
  * 将格式化代码（Prettier/Lint）与逻辑修改混在一个 Commit 中。
  * 提交包含大量未完成功能的庞大 Commit（"Giant Commit"）。

### 2. 提交信息规范 (Commit Messages)

清晰的 Commit Message 是团队沟通的桥梁。目前最流行的是 **Conventional Commits** 规范。

**格式结构：**

```text
<type>(<scope>): <subject>
// 空一行
<body>
// 空一行
<footer>
```

* **Type（类型）：**
  * `feat`: 新功能
  * `fix`: 修复 Bug
  * `docs`: 文档修改
  * `style`: 代码格式修改（不影响逻辑，如空格、分号）
  * `refactor`: 代码重构（既不修复 Bug 也不添加功能）
  * `test`: 测试用例修改
  * `chore`: 构建过程或辅助工具的变动
* **Subject（标题）：** 简短描述（50字符以内），使用祈使句（如 "Add login" 而非 "Added login"）。
* **Body（正文）：** 解释*为什么*要修改，以及与之前行为的差异。
* **Footer（脚注）：** 关联 Issue（如 `Closes #123`）。

**示例：**

```text
fix(auth): handle invalid token error

Ensure the user is redirected to login page when the API returns a 401 error.

Closes #42
```

### 3. 分支管理策略 (Branching Strategy)

不要直接在主分支（`main` 或 `master`）上工作。选择适合团队的工作流（如 GitHub Flow, Git Flow 或 Trunk-Based Development）。

* **分支命名规范：**
  * `feature/login-page`
  * `bugfix/header-alignment`
  * `hotfix/production-crash`
  * `refactor/database-layer`
* **主分支保护：**
  * 在 GitHub/GitLab 设置中锁定 `main`/`master` 分支，禁止直接 Push。
  * 所有代码必须通过 **Pull Request (PR)** 或 **Merge Request (MR)** 才能合并。

### 4. 合并与历史管理 (Merging & History)

**Rebase (变基) vs. Merge (合并)**

* **本地分支：使用 Rebase。**
  * 在将你的功能分支合并回主分支之前，先在本地 `git pull --rebase origin main`。这能确保你的提交历史是线性的，没有多余的 "Merge branch 'main' into..." 提交。
* **公共分支：使用 Merge。**
  * 一旦分支推送到远端并被他人基于此开发，**绝对不要**使用 Rebase 修改历史，否则会造成团队灾难。
* **合并到主分支时：推荐 Squash Merge。**
  * 在 PR 合并时，使用 "Squash and Merge" 将你开发过程中的琐碎提交（"wip", "typo", "fix again"）压缩成一个整洁的提交记录到主分支。

### 5. 安全与配置 (Safety & Configuration)

* **善用 `.gitignore`：**
  * **绝对禁止**提交：
    * 依赖包文件夹 (`node_modules/`, `venv/`)
    * 构建产物 (`dist/`, `build/`, `.o`, `.exe`)
    * 操作系统文件 (`.DS_Store`, `Thumbs.db`)
    * **敏感信息** (`.env`, `config.js` 中的密码、API Key)
  * *技巧：可以在项目根目录放置一个 `.gitignore` 模板。*
* **不要修改公共历史：**
  * 永远不要对已经推送到远程仓库的公共分支执行 `git push --force`（除非你是唯一的维护者且知道自己在做什么）。如果必须修正，请使用 `git push --force-with-lease`（稍微安全一点）。
  * 如果提交错了代码，优先使用 `git revert` 生成一个新的反向提交，而不是 `git reset` 删除历史。

### 6. 工作流检查清单 (TL;DR Workflow)

1. **拉取最新代码：** `git checkout main` -> `git pull`
2. **创建新分支：** `git checkout -b feature/my-cool-feature`
3. **开发与提交：**
    * 修改代码
    * `git add .`
    * `git commit -m "feat: add cool feature logic"`
4. **保持同步（避免冲突）：**
    * `git fetch origin`
    * `git rebase origin/main` (解决可能产生的冲突)
5. **推送分支：** `git push origin feature/my-cool-feature`
6. **发起 PR/MR：** 请求代码审查。
7. **修正代码：** 根据审查意见修改，再次 Push（会自动更新 PR）。
8. **合并：** 审查通过后，合并进主分支。
