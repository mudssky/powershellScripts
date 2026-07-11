## Context

当前项目的 shell 配置架构采用模块化片段系统（`.bashrc.d/`），源文件位于 `linux/.bashrc.d/`，通过 `linux/01manage-shell-snippet.sh` symlink 部署到 `~/.bashrc.d/`。`~/.bashrc` 和 `~/.zshrc` 均可加载这些片段。

现状问题：

1. 源文件在 `linux/` 下但 macOS 也在使用，命名产生语义歧义
2. macOS `01install.sh` 未调用部署工具，全新 macOS 环境下 `~/.bashrc.d/` 可能为空
3. `fzf-history.sh` 仅 Bash、`zoxide init` 硬编码 `bash`、`ls --color=auto` 与 BSD ls 不兼容、`/dev/tcp` 不支持 Zsh
4. macOS `.zshrc` 中 `fnm` 初始化与 `node.sh` 重复

macOS 确认使用 Zsh 作为默认 shell，不安装额外的 Bash。

## Goals / Non-Goals

**Goals:**

- 将共享 shell 片段提升为平台无关的 `shell/` 顶级目录
- 支持 `shared.d/`（通用）+ `bash.d/`（Bash only）+ `zsh.d/`（Zsh only）三层分离
- 修复所有片段的 Zsh 兼容性问题
- 统一 Linux/macOS 部署流程，一个 `shell/deploy.sh` 搞定
- 清理 macOS `.zshrc` 中与 `.bashrc.d/` 片段重复的配置

**Non-Goals:**

- 不引入 chezmoi/yadm 等 dotfile 管理器
- 不修改 PowerShell profile 系统（`profile/` 目录）
- 不为 macOS 安装 Bash 5
- 不重构 `linux/ubuntu/` 下的 legacy Zsh 配置（Oh-My-Zsh + Powerlevel10k）
- 不修改 Hammerspoon 配置

## Decisions

### 1. 目录结构设计

```text
shell/
├── shared.d/           ← 原 linux/.bashrc.d/ 中通用片段（Bash/Zsh 通用）
│   ├── aliases.sh
│   ├── proxy.sh
│   ├── path.sh
│   ├── node.sh
│   ├── python.sh
│   ├── java.sh
│   ├── ai.sh
│   └── env.local.sh
├── bash.d/             ← Bash 专属片段
│   └── fzf-history.sh  ← 原 fzf-history.sh（使用 bind -x / READLINE_LINE）
├── zsh.d/              ← Zsh 专属片段
│   └── fzf-history.zsh ← fzf-history 的 Zsh 版本（使用 zle widget）
└── deploy.sh           ← 原 linux/01manage-shell-snippet.sh
```

**理由**: 三层分离让通用代码零重复，shell 专属代码各自独立。`fzf-history` 由于 Bash (`bind -x` + `READLINE_LINE`) 和 Zsh (`zle` widget + `BUFFER`) 的键绑定机制差异太大，不适合用 `$ZSH_VERSION` 条件分支合并到一个文件，拆成两个文件更清晰。

**备选方案**: 将所有片段都放在 `shared.d/` 并用 `if [ -n "$ZSH_VERSION" ]` 分支 — 对于简单差异可行（如 zoxide init），但对 fzf-history 这种整个文件逻辑不同的���景会让代码可读性变差。

### 2. 部署策略

`deploy.sh` 将：

1. 创建 `~/.bashrc.d/` 目录
2. symlink `shared.d/*.sh` 到 `~/.bashrc.d/`
3. 检测当前 shell：
   - Bash: 额外 symlink `bash.d/*.sh` 到 `~/.bashrc.d/`
   - Zsh: 额外 symlink `zsh.d/*.zsh`（重命名为 `.sh`）到 `~/.bashrc.d/`
4. 确保 `~/.bashrc`（Bash）或 `~/.zshrc`（Zsh）包含 loader 代码

**理由**: 部署后 `~/.bashrc.d/` 仍然是统一的加载目录，loader 代码不需要区分 `shared.d` 和 `bash.d`/`zsh.d`。简单直接。

**Shell 检测方式**: 使用 `basename "$SHELL"` 检测用户默认 shell，而非 `$BASH_VERSION`/`$ZSH_VERSION`（后者检测的是当前运行脚本的 shell，而 `deploy.sh` 可能由 bash 执行但用户的登录 shell 是 zsh）。同时支持 `--shell bash|zsh` 参数手动指定。

### 3. 兼容性修复方案

| 文件 | 问题 | 修复方式 |
|------|------|----------|
| `aliases.sh:98` | `zoxide init bash` 硬编码 | 改为 `if [ -n "$ZSH_VERSION" ]; then eval "$(zoxide init zsh)"; else eval "$(zoxide init bash)"; fi` |
| `aliases.sh:41-46` | `ls --color=auto` macOS 不兼容 | 非 eza 分支改为 `uname -s` 检测：Darwin 用 `-G`，Linux 用 `--color=auto` |
| `proxy.sh:44` | `/dev/tcp` Bash 专属 | 改用 `timeout 0.1 nc -z "$host" "$port"` 或 `curl --connect-timeout 0.1 "http://${host}:${port}"` |
| `fzf-history.sh` | 仅 Bash | 保持不变，移到 `bash.d/`；新建 `zsh.d/fzf-history.zsh` 用 `zle` widget 实现同功能 |

### 4. macOS `.zshrc` 清理

清理 `macos/config/.zshrc` 中与 `shared.d/` 片段重复的部分：

- `fnm` 初始化已在 `node.sh` 中 → 从 `.zshrc` 移除
- `pyenv` 初始化不在 `shared.d/` 中 → 保留在 `.zshrc`（或新增 `shared.d/pyenv.sh`，但由于 Linux 侧未使用 pyenv 则保留在 `.zshrc`）
- Homebrew PATH、Hammerspoon 配置、Ollama 配置 → 保留在 `.zshrc`（macOS 专属）
- `command_exists` 函数定义 → 移除，各片段使用 `command -v` 直接检测

### 5. `linux/` 目录残留处理

迁移后 `linux/` 目录保留：

- `02installHomeBrew.sh` — Linux 系统安装脚本
- `ubuntu/` — Ubuntu 专属配置和安装工具
- `wsl2/` — WSL2 专属配置
- `arch/` — Arch Linux 配置

删除：

- `linux/.bashrc.d/` — 已迁移至 `shell/shared.d/`
- `linux/01manage-shell-snippet.sh` — 已迁移至 `shell/deploy.sh`

## Risks / Trade-offs

- **已部署 symlink 失效** → Symlink 目标路径从 `linux/.bashrc.d/` 变为 `shell/shared.d/`，已有环境需要重新运行 `deploy.sh` 才能生效。用户在迁移后首次打开终端可能看到 "source 失败" 的警告（因为旧 symlink 指向已不���在的路径）。**缓解**: 在 deploy.sh 中加入旧 symlink 清理逻辑。
- **`nc` 命令可用性** → macOS 自带 `nc`（netcat），Linux 可能需要 `apt install netcat-openbsd`。但考虑到 proxy 连通性检测只是锦上添花，失败也不影响核心功能。**缓解**: 用 `command -v nc` 检测，不可用时 fallback 到 `curl --connect-timeout 0.1`。
- **Zsh fzf-history 功能差异** → Zsh 的 `zle` widget 与 Bash 的 `bind -x` 机制不同，行为可能有细微差异。**缓解**: 充分测试 Enter/Ctrl-E/Ctrl-Y 三种模式。
- **`deploy.sh` 使用 `BASH_SOURCE[0]` 定位源目录** → 如果脚本被 `source` 而非直接执行，路径解析可能不同。原脚本已处理此问题（解引用 symlink 循环），保持相同逻辑即可。需要额外注意支持从 macOS `01install.sh`（Zsh 脚本）调用的场景。**缓解**: `deploy.sh` 保持 `#!/bin/bash` shebang，macOS 调用时通过 `bash shell/deploy.sh` 显式调用。
