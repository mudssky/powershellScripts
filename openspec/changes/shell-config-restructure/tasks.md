## 1. 目录结构迁移

- [x] 1.1 创建 `shell/shared.d/`、`shell/bash.d/`、`shell/zsh.d/` 目录
- [x] 1.2 将 `linux/.bashrc.d/` 中的通用片段（aliases.sh、proxy.sh、path.sh、node.sh、python.sh、java.sh、ai.sh、env.local.sh）移动到 `shell/shared.d/`
- [x] 1.3 将 `linux/.bashrc.d/fzf-history.sh` 移动到 `shell/bash.d/fzf-history.sh`
- [x] 1.4 将 `linux/01manage-shell-snippet.sh` 移动到 `shell/deploy.sh`
- [x] 1.5 删除空的 `linux/.bashrc.d/` 目录和 `linux/01manage-shell-snippet.sh`

## 2. 兼容性修复（shared.d 片段）

- [x] 2.1 修复 `aliases.sh` 中 `zoxide init` 硬编码为 `bash` 的问题，改为 `$ZSH_VERSION` 动态检测
- [x] 2.2 修复 `aliases.sh` 中 `ls` 别名的 macOS BSD ls 兼容性（`--color=auto` → Darwin 下用 `-G`）
- [x] 2.3 修复 `proxy.sh` 中 `/dev/tcp` Bash 专属特性，改用 `nc -z` 或 `curl --connect-timeout` 并做 fallback

## 3. Zsh 专属片段

- [x] 3.1 创建 `shell/zsh.d/fzf-history.zsh`，使用 `zle` widget 实现与 Bash 版本对等的 fzf 历史搜索功能（Alt+h 绑定、Enter/Ctrl-E/Ctrl-Y 三种模式）

## 4. 部署脚本更新

- [x] 4.1 更新 `shell/deploy.sh`：修改源目录路径从 `.bashrc.d` 为 `shared.d`
- [x] 4.2 更新 `shell/deploy.sh`：添加 `--shell bash|zsh` 参数支持，默认通过 `basename "$SHELL"` 检测
- [x] 4.3 更新 `shell/deploy.sh`：根据检测到的 shell 类型额外部署 `bash.d/` 或 `zsh.d/` 片段
- [x] 4.4 更新 `shell/deploy.sh`：添加旧 symlink 清理逻辑（删除 `~/.bashrc.d/` 中指向不存在路径的 symlink）

## 5. macOS 配置更新

- [x] 5.1 更新 `macos/01install.sh`：在安装流程末尾调用 `shell/deploy.sh` 部署 `.bashrc.d/` 片段
- [x] 5.2 清理 `macos/config/.zshrc`：移除 `fnm` 初始化代码（已由 `node.sh` 提供）
- [x] 5.3 清理 `macos/config/.zshrc`：移除 `command_exists` 函数定义（各片段直接使用 `command -v`）

## 6. 验证

- [x] 6.1 验证 `shell/shared.d/` 中所有片段在 Bash 下能正常 source（无语法错误）
- [x] 6.2 验证 `shell/deploy.sh --dry-run` 输出正确的 symlink 计划
- [x] 6.3 验证 `shell/deploy.sh --shell zsh --dry-run` 正确选择 `zsh.d/` 片段
