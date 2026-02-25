## 1. 创建 Starship 初始化片段

- [ ] 1.1 创建 `shell/shared.d/zz-prompt.sh`，包含 `command -v starship` 守卫、shell 类型检测（`$ZSH_VERSION` / `$BASH_VERSION`）和对应的 `eval "$(starship init <shell>)"`

## 2. 验证

- [ ] 2.1 确认 `shell/deploy.sh --shell zsh --dry-run` 能正确识别并包含 `zz-prompt.sh`
- [ ] 2.2 确认 `shell/deploy.sh --shell bash --dry-run` 能正确识别并包含 `zz-prompt.sh`
