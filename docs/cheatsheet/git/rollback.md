Git 回滚代码的最佳实践取决于**代码当前的状态**（是只在本地，还是已经推送到远程仓库）。

核心原则是：**对于已经推送到公共仓库（远程）的代码，永远不要修改历史（Rewrite History），而是通过“新增”一个反向操作来抵消错误。**

以下是针对不同场景的最佳实践指南：

---

### 场景 1：代码已推送到远程 (Remote) —— ❌ 紧急且危险

**场景：** 你提交了代码，推送到 GitHub/GitLab `main` 分支，然后发现是个 Bug。
**最佳实践：** 使用 `git revert`。

* **为什么？** `git revert` 会创建一个**新的提交**，这个提交的内容是撤销之前的更改。它不会删除历史记录，这保证了团队其他成员的代码库不会乱套。
* **命令：**

    ```bash
    # 撤销最近一次提交
    git revert HEAD

    # 撤销指定的某次提交 (commit-hash)
    git revert <commit_hash>
    ```

* **注意：** 此时会弹出编辑器让你写 Commit Message，默认即可，保存退出后 Push。

---

### 场景 2：代码已 Commit 但未 Push (Local) —— ✅ 安全区域

**场景：** 你在本地 commit 了代码，觉得写得太烂想重写，或者想撤销这个 commit。
**最佳实践：** 使用 `git reset`。

`git reset` 有三种模式，根据你想保留多少数据来选择：

1. **推荐：保留代码，只撤销 Commit 记录 (Soft Reset)**
    * **命令：** `git reset --soft HEAD~1`
    * **效果：** 你的代码变回了 `git add` 之后（Staged）的状态。你可以修改代码后重新提交。这是最常用的方式。

2. **保留代码，撤销 Commit 和 Add (Mixed Reset)**
    * **命令：** `git reset HEAD~1` (默认模式)
    * **效果：** 你的代码变回了 `git add` 之前（Unstaged）的状态。

3. **危险：彻底删除代码和记录 (Hard Reset)**
    * **命令：** `git reset --hard HEAD~1`
    * **效果：** **警告！** 你的修改会彻底消失，回到上一次提交时的状态。只有在你确定刚才写的全是垃圾且完全不需要保留时才用。

---

### 场景 3：只是写错了 Commit Message 或漏提交了文件

**场景：** 刚敲完 `git commit -m "feat: login"`, 突然发现漏了一个文件没 `add`，或者注释写错了。
**最佳实践：** 使用 `git commit --amend`。

* **操作：**
    1. `git add <漏掉的文件>` (如果是只改注释，这步跳过)
    2. `git commit --amend`
* **效果：** 这不会产生新的 Commit，而是直接“修正”上一次的 Commit。
* **注意：** 如果这个 commit 已经推送到远程了，不要用这个命令（除非是你一个人的分支），否则需要强制推送。

---

### 场景 4：代码还没 Commit (在工作区)

**场景：** 你改乱了一个文件，想把它恢复成服务器上的原样。
**最佳实践：** 使用 `git restore` (新版 Git) 或 `git checkout` (旧版习惯)。

* **推荐 (Git 2.23+)：**

    ```bash
    # 丢弃工作区某个文件的修改
    git restore <filename>
    ```

* **旧版习惯：**

    ```bash
    git checkout -- <filename>
    ```

---

### 场景 5：救命稻草 —— 误删了代码怎么办？

**场景：** 你手滑执行了 `git reset --hard`，发现刚才辛苦写的代码全没了。
**最佳实践：** 使用 `git reflog` 找回。

Git 会记录你的每一次 HEAD 变动（即使是被删除的 commit）。

1. 输入 `git reflog`，你会看到类似的操作记录：

    ```text
    e5b1a2c HEAD@{0}: reset: moving to HEAD~1
    8a2b3c4 HEAD@{1}: commit: feat: my lost code
    ```

2. 找到你误删之前的那个 commit hash (例如 `8a2b3c4`)。
3. 执行 `git reset --hard 8a2b3c4`。
4. **复活成功！**

---

### 总结：决策流程图

1. **代码 Push 了吗？**
    * **是 (Yes):** 必须用 **`git revert`**。 (严禁 `reset` 后强推，除非是你个人的 Feature 分支)
    * **否 (No):**
        * **完全不要这些改动了？** -> **`git reset --hard`**
        * **想保留改动，重新提交？** -> **`git reset --soft`**
        * **只是漏了文件/写错注释？** -> **`git commit --amend`**
        * **还没 Commit，只是改乱了文件？** -> **`git restore`**

### 专家提示 (Pro Tip)

如果你在一个只有你一个人使用的远程分支（Feature Branch）上工作，并且你确实想整理 Commit 历史（比如把10个琐碎提交变成1个），你可以使用 `git rebase -i` 或 `git reset`，然后使用 **`git push --force-with-lease`**。

* **不要使用** `--force`，因为它会无脑覆盖。
* **使用** `--force-with-lease`，它会检查远程分支在你拉取后是否被别人更新过。如果有别人提交了代码，它会阻止你覆盖，从而保护队友的代码。
