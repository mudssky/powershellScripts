## Why

macOS 和 Linux 的 Bash/Zsh 原生 shell 缺少 Starship prompt 初始化。PowerShell profile 已有完善的 Starship 集成（带缓存优化），但 `shell/shared.d/` 片段系统中没有对应的 prompt 配置，导致通过 `shell/deploy.sh` 部署的 Bash/Zsh 会话使用原生 prompt。

## What Changes

- 新增 `shell/shared.d/zz-prompt.sh` 片段，为 Bash 和 Zsh 提供 Starship 初始化
- 使用 `zz-` 前缀确保在所有其他片段之后加载（PATH 等环境变量已就绪）
- 使用默认 Starship 配置，不引入 `starship.toml`
- 加入 `command -v starship` 守卫，未安装时静默跳过

## Capabilities

### New Capabilities

- `starship-shell-init`: Bash/Zsh 原生 shell 的 Starship prompt 初始化片段

### Modified Capabilities

（无）

## Impact

- 新增文件：`shell/shared.d/zz-prompt.sh`
- 影响范围：所有通过 `shell/deploy.sh` 部署的 Bash/Zsh 会话
- 依赖：`starship` CLI 已通过 `apps-config.json` 的 homebrew 条目覆盖安装
- 无破坏性变更：未安装 starship 时行为不变
