## Why

当前跨平台共享的 shell 配置片段（`.bashrc.d/`）存放在 `linux/` 目录下，但 macOS 也在使用这些片段。目录归属存在语义歧义，且 macOS 的部署流程存在缺口——`macos/01install.sh` 没有调用 snippet 管理脚本来部署 `.bashrc.d/` 片段到 `~/.bashrc.d/`。此外，部分片段存在跨 shell（Bash/Zsh）兼容性问题（如 `zoxide init` 写死 `bash`、`ls --color=auto` 在 macOS BSD ls 下不可用、`/dev/tcp` 是 Bash 专属特性、`fzf-history.sh` 仅支持 Bash）。macOS 决定继续使用 Zsh 作为默认 shell，因此需要修复这些兼容性问题并统一部署流程。

## What Changes

- 将 `linux/.bashrc.d/` 提升为平台无关的顶级目录 `shell/shared.d/`，消除语义歧义
- 将 `linux/01manage-shell-snippet.sh` 迁移为 `shell/deploy.sh`，作为统一部署工具
- 新增 `shell/bash.d/` 存放 Bash 专属片段（如 `fzf-history.sh`）
- 新增 `shell/zsh.d/` 存放 Zsh 专属片段（如 fzf-history 的 Zsh zle widget 版本）
- 修复 `aliases.sh` 中 `zoxide init` 硬编码为 `bash` 的问题，��为动态检测当前 shell
- 修复 `aliases.sh` 中 `ls` 别名在 macOS BSD ls 下不兼容的问题（`--color=auto` → `-G` 或依赖 eza）
- 修复 `proxy.sh` 中 `/dev/tcp` Bash 专属特性在 Zsh 下不可用的问题
- 更新 `macos/01install.sh` 调用 `shell/deploy.sh` 来部署配置片段
- 清理 macOS `.zshrc` 中与 `.bashrc.d/` 片段重复的初始化逻辑（如 `fnm`）
- 更新 `deploy.sh` 支持根据当前 shell 分别加载 `shared.d/` + `bash.d/` 或 `shared.d/` + `zsh.d/`

## Capabilities

### New Capabilities
- `shell-config-structure`: 跨平台 shell 配置的目录结构重组，将共享片段从 `linux/` 提升为独立的 `shell/` 顶级目录
- `shell-snippet-compat`: shell 配置片段的 Bash/Zsh 双 shell 兼容性，包含 zoxide、ls、proxy、fzf-history 等修复
- `shell-deploy-unified`: 统一的 shell 配置部署工具，支持 Linux/macOS 双平台、Bash/Zsh 双 shell 的自动部署

### Modified Capabilities

（无已有 spec 需要修改）

## Impact

- **文件移动**: `linux/.bashrc.d/*.sh` → `shell/shared.d/*.sh`，`linux/01manage-shell-snippet.sh` → `shell/deploy.sh`
- **受影响脚本**: `macos/01install.sh`（需增加部署调用）、`macos/config/.zshrc`（清理重复配置）
- **已有 symlink**: 已部署在 `~/.bashrc.d/` 的 symlink 目标路径会变化，��要重新部署
- **`linux/` 目录**: 仅保留平台专属的安装脚本（如 `02installHomeBrew.sh`、`ubuntu/` 子目录等）
- **无破坏性变更**: 最终用户侧的 `~/.bashrc.d/` 加载机制和文件名均保持不变
