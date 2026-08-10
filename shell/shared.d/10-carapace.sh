# Carapace 参数补全：仅在交互式 Bash/Zsh 中初始化，失败时保留原生补全。
case $- in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

if [ "${__powershell_scripts_carapace_initialized:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi
command -v carapace >/dev/null 2>&1 || return 0 2>/dev/null || exit 0
if [ -n "${BASH_VERSION:-}" ]; then
  __powershell_scripts_carapace_shell=bash
elif [ -n "${ZSH_VERSION:-}" ]; then
  __powershell_scripts_carapace_shell=zsh
else
  return 0 2>/dev/null || exit 0
fi

__powershell_scripts_carapace_init="$(carapace _carapace "$__powershell_scripts_carapace_shell" 2>/dev/null)" || {
  unset __powershell_scripts_carapace_init __powershell_scripts_carapace_shell
  return 0 2>/dev/null || exit 0
}
if [ -n "$__powershell_scripts_carapace_init" ] && eval "$__powershell_scripts_carapace_init" 2>/dev/null; then
  __powershell_scripts_carapace_initialized=1
fi
unset __powershell_scripts_carapace_init __powershell_scripts_carapace_shell
