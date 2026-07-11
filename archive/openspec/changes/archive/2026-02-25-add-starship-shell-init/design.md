## Context

当前 `shell/shared.d/` 片段系统为 Bash/Zsh 提供模块化配置（别名、代理、PATH、工具初始化等），通过 `shell/deploy.sh` 部署为 `~/.bashrc.d/` 下的 symlink。片段按文件名字母序加载。

PowerShell 侧已有成熟的 Starship 集成（`profile/features/environment.ps1`），包含文件缓存和 continuation prompt 内联优化。Bash/Zsh 侧缺少对应的 prompt 初始化。

Starship 已在 `apps-config.json` 的 homebrew 条目中注册（`supportOs: ["linux", "macOS"]`），安装路径已覆盖。

## Goals / Non-Goals

**Goals:**

- 为 Bash 和 Zsh 提供 Starship prompt 初始化
- 遵循现有片段系统的约定（`shared.d/` 放通用片段、`command -v` 守卫）
- 确保加载顺序正确（在 PATH 等环境变量就绪后加载）

**Non-Goals:**

- 不引入 `starship.toml` 自定义配置（使用默认配置）
- 不为 Bash/Zsh 实现类似 PowerShell 的缓存优化（Starship 原生 init 已足够快）
- 不修改 PowerShell 侧的 Starship 集成
- 不修改 `linux/ubuntu/` 下的 legacy Oh-My-Zsh 配置

## Decisions

### 1. 文件命名：`zz-prompt.sh`

使用 `zz-` 前缀确保在所有其他片段之后加载。Starship init 需要 PATH 已包含相关工具路径（如 `path.sh` 添加的 `bin/` 和 `~/.cargo/bin`），排在最后可避免顺序依赖问题。

替代方案：`99-prompt.sh` — 数字前缀也可行，但现有片段均使用语义化命名，`zz-` 更一致。

### 2. 放置位置：`shared.d/` 而非 `zsh.d/`

Starship 同时支持 Bash 和 Zsh，`eval "$(starship init bash)"` 和 `eval "$(starship init zsh)"` 通过检测 `$ZSH_VERSION` / `$BASH_VERSION` 动态选择。放 `shared.d/` 一份文件覆盖两种 shell。

现有 `shared.d/aliases.sh` 已有类似的 shell 类型动态检测模式（zoxide init 部分）。

### 3. 守卫策略：`command -v starship` 静默跳过

与现有片段一致（如 `node.sh` 的 `command -v fnm` 守卫）。未安装 starship 时不输出任何提示，保持 shell 启动干净。

## Risks / Trade-offs

- [风险] Starship init 增加 shell 启动时间（约 20-50ms） → 可接受，Starship 本身已高度优化，且用户明确选择使用
- [风险] 与 `macos/config/.zshrc` 中可能的手动 prompt 配置冲突 → 当前 `.zshrc` 无 prompt 配置，无冲突
