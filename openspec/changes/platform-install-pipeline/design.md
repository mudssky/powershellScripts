## Context

当前两个平台的安装脚本已有编号约定（00-xx），但存在职责混合、步骤缺失、无 manifest 文档的问题。本变更在 `shell-config-restructure` 完成后执行，`shell/deploy.sh` 已可用。

现有脚本清单：
- **Linux**: `00quickstart.sh`（拉仓库）→ `01manage-shell-snippet.sh`（将迁移）→ `02installHomeBrew.sh`（Homebrew + PowerShell 混合）→ `03installApps.ps1`（应用安装）
- **macOS**: `01install.sh`（Homebrew + .zshrc + PowerShell 混合）→ `02installApp.ps1`（应用安装）

## Goals / Non-Goals

**Goals:**
- 每个平台有完整的、单一职责的编号脚本链
- 每个平台有 `INSTALL.md` 作为 agent 可读的执行 manifest
- INSTALL.md 包含仓库拉取指引，支持从零开始的全新环境安装
- 拆分混合职责脚本（Homebrew/PowerShell 分离）

**Non-Goals:**
- 不重写脚本内部逻辑（仅拆分和重新编号）
- 不修改 `ubuntu/installer/` 下的子安装脚本
- 不创建自动化执行器（agent 直接读 INSTALL.md 按步骤执行即可）
- 不处理 `linux/archlinux/`、`linux/wsl2/` 等子平台变体

## Decisions

### 1. Linux 安装流水线编号

```
linux/
├── INSTALL.md                  ← 新增：manifest 文档
├── 00quickstart.sh             ← 保持：拉取仓库
├── 01installHomeBrew.sh        ← 重命名自 02，仅保留 Homebrew 安装
├── 02installPowerShell.sh      ← 新增：从原 02 拆出 PowerShell 安装
├── 03deployShellConfig.sh      ← 新增：调用 shell/deploy.sh
├── 04installApps.ps1           ← 重命名自 03
```

**理由**: `01manage-shell-snippet.sh` 已迁移到 `shell/deploy.sh`，空出编号。Homebrew 和 PowerShell 拆分后各自独立，便于跳过或单独重试。shell 配置部署作为独立步骤插入。

### 2. macOS 安装流水线编号

```
macos/
├── INSTALL.md                  ← 新增：manifest 文档
├── 01installHomeBrew.sh        ← 重构自原 01install.sh，仅 Homebrew
├── 02installPowerShell.sh      ← 新增：从原 01 拆出 PowerShell 安装
├── 03deployShellConfig.sh      ← 新增：调用 shell/deploy.sh + ln .zshrc
├── 04installApps.ps1           ← 重命名自 02installApp.ps1
├── 05deployHammerspoon.sh      ← 新增：调用 hammerspoon/load_scripts.zsh
```

**理由**: macOS 不需要 `00quickstart`（INSTALL.md 文档中会包含 clone 指引，但不作为编号脚本）。`.zshrc` 的 symlink 从原 `01install.sh` 移到 `03deployShellConfig.sh` 中，与 shell 配置部署合并。

### 3. INSTALL.md 格式设计

采用结构化 Markdown，每个步骤包含固定字段：

```markdown
## 0. 拉取仓库

- **脚本**: （手动执行 / 00quickstart.sh）
- **执行方式**: `bash`
- **前置条件**: 网络连接、git
- **可跳过**: 否
- **说明**: ...

## 1. 安装 Homebrew

- **脚本**: `01installHomeBrew.sh`
- **执行方式**: `bash`
- **前置条件**: 网络连接
- **可跳过**: 是（如已安装 Homebrew）
- **说明**: ...
```

**理由**: Markdown 人类可读，agent 也能通过固定字段名解析。每个步骤的"前置条件"和"可跳过"字段让 agent 能做智能判断。

### 4. macOS INSTALL.md 中的仓库拉取指引

macOS 没有 `00quickstart.sh` 脚本，但 INSTALL.md 的第 0 步会包含手动 clone 命令：

```markdown
## 0. 拉取仓库

- **脚本**: 无（手动执行以下命令）
- **执行方式**: 手动
- **前置条件**: git、网络连接
- **可跳过**: 是（如仓库已存在）
- **说明**: 通过 GitHub 网页引导 AI agent 执行
```

**理由**: macOS 用户通常已有 git（Xcode Command Line Tools），不需要像 Linux 那样先 `apt install gh`。

## Risks / Trade-offs

- **脚本重命名影响引用** → 检查是否有其他脚本或文档引用了旧文件名（如 `国内linux环境安装.md` 中提到的步骤）。**缓解**: 全局搜索旧文件名，更新引用。
- **拆分后的 PowerShell 安装脚本需要处理两种安装方式** → Linux 上有本地 deb + fallback 到 installer 脚本的逻辑，macOS 上是 `brew install --cask powershell`。各自独立实现即可。
- **INSTALL.md 与脚本不同步** → 新增/删除脚本时需要同步更新 INSTALL.md。**缓解**: 在 INSTALL.md 中注明"此文档需与目录下的脚本保持同步"。
