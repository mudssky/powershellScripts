# ======================================================================
# 文件：90-atuin.sh
# 作用：在交互式 Bash/Zsh 中初始化 Atuin 历史，并保留原生 Up 键。
# 兼容性：Bash / Zsh 交互式 shell。
# ======================================================================

# -- interactive guard --------------------------------------------------
case $- in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

if [ "${__powershell_scripts_atuin_initialized:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi
command -v atuin >/dev/null 2>&1 || return 0 2>/dev/null || exit 0

# -- shell-specific initialization --------------------------------------
if [ -n "${BASH_VERSION:-}" ]; then
  __powershell_scripts_atuin_shell='bash'
elif [ -n "${ZSH_VERSION:-}" ]; then
  __powershell_scripts_atuin_shell='zsh'
else
  return 0 2>/dev/null || exit 0
fi

__powershell_scripts_atuin_init="$(atuin init "$__powershell_scripts_atuin_shell" --disable-up-arrow 2>/dev/null)" || {
  unset __powershell_scripts_atuin_init __powershell_scripts_atuin_shell
  return 0 2>/dev/null || exit 0
}
if [ -n "$__powershell_scripts_atuin_init" ] && eval "$__powershell_scripts_atuin_init"; then
  __powershell_scripts_atuin_initialized=1
fi
unset __powershell_scripts_atuin_init __powershell_scripts_atuin_shell
