# Worktrunk (wt) Cheatsheet

Worktrunk 是一个用于管理 Git worktree 的 CLI 工具，专为并行 AI Agent 工作流设计。它可以简化创建和管理 git worktrees 的过程，让每个 Agent 拥有独立的工作目录。

## 安装 (Installation)

### Homebrew (macOS & Linux)
```bash
brew install worktrunk
wt config shell install
```

### Cargo
```bash
cargo install worktrunk
wt config shell install
```

### Windows (Winget)
```bash
winget install max-sixty.worktrunk
git-wt config shell install
# 注意: 默认为 'git-wt' 以避免与 Windows Terminal ('wt') 冲突。
# 如果想直接使用 'wt'，需禁用 Windows Terminal 的别名。
```

### Arch Linux
```bash
paru worktrunk-bin
wt config shell install
```

## 常用命令 (Common Commands)

| 任务 | Worktrunk (`wt`) | 原生 Git |
|------|------------------|-----------|
| **切换/创建** | `wt switch feat` | `cd ../repo.feat` |
| **新建分支并切换** | `wt switch -c feat` | `git worktree add -b feat ../repo.feat && cd ../repo.feat` |
| **启动 Agent** | `wt switch -c -x claude feat` | `... && claude` |
| **清理** | `wt remove` | `cd ../repo && git worktree remove ... && git branch -d ...` |
| **列表状态** | `wt list` | `git worktree list` |

## 快速开始工作流 (Quick Start Workflow)

1.  **创建新功能 worktree**:
    这会自动创建分支、创建目录并切换过去。
    ```bash
    wt switch --create feature-auth
    ```

2.  **查看 worktrees 列表**:
    ```bash
    wt list
    ```
    输出示例:
    ```text
      Branch        Status        HEAD±    main↕  Remote⇅  Commit    Age   Message
    @ feature-auth  +   –      +53                         0e631add  1d    Initial commit
    ^ main              ^⇡                         ⇡1      0e631add  1d    Initial commit
    ```
    (`@` 表示当前 worktree, `+` 表示有未提交更改)

3.  **合并与清理**:
    
    **本地合并 (Local Merge)**:
    将当前更改 squash、rebase 并合并到 main 分支。
    **注意：合并成功后，`wt` 会自动在后台删除当前 worktree 和分支。**
    ```bash
    wt merge main
    ```

    **PR 工作流 (Pull Request)**:
    提交、推送、创建 PR，合并后手动清理。
    ```bash
    wt step commit    # 提交暂存更改
    gh pr create      # 创建 PR
    wt remove         # PR 合并后，清理本地 worktree
    ```

## 并行 Agents (Parallel Agents)

为并行任务创建多个 worktrees 并直接运行命令（如启动 Claude）：

```bash
wt switch -x claude -c feature-a -- 'Add user authentication'
wt switch -x claude -c feature-b -- 'Fix the pagination bug'
```
(`-x` 标志在切换后执行命令)

## 配置 (Configuration)

为了使 `wt` 能够更改当前 shell 的目录 (`cd`)，必须安装 shell 集成：
```bash
wt config shell install
```
