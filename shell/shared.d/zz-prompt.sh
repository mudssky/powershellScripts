# ======================================================================
# 文件：zz-prompt.sh
# 作用：初始化 Starship prompt 与 zoxide，并提供 zoxide 快捷别名。
# 兼容性：Bash / Zsh。
# ======================================================================

# -- prompt -------------------------------------------------------------
if command -v starship &> /dev/null; then
  if [ -n "$ZSH_VERSION" ]; then
    eval "$(starship init zsh)"
  elif [ -n "$BASH_VERSION" ]; then
    eval "$(starship init bash)"
  fi
fi

# -- zoxide -------------------------------------------------------------
if command -v zoxide &> /dev/null; then
  if [ -n "$ZSH_VERSION" ]; then
    eval "$(zoxide init zsh)"
  else
    eval "$(zoxide init bash)"
  fi
  alias zq='zoxide query'
  alias za='zoxide add'
  alias zr='zoxide remove'
fi
