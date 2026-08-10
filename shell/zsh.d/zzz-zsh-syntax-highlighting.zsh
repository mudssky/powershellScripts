# Zsh Syntax Highlighting：必须位于其它 widget 与 prompt 初始化之后。
if [[ -z ${ZSH_VERSION:-} || ! -o interactive ]]; then
  return 0
fi

if [[ ${__powershell_scripts_zsh_syntax_highlighting_initialized:-0} == 1 ]]; then
  return 0
fi
if (( ${+functions[_zsh_highlight]} )); then
  typeset -g __powershell_scripts_zsh_syntax_highlighting_initialized=1
  return 0
fi

for _powershell_scripts_zsh_plugin_prefix in \
  "${POWERSHELL_SCRIPTS_HOMEBREW_PREFIX:-}" \
  "${HOMEBREW_PREFIX:-}" \
  /opt/homebrew \
  /usr/local; do
  [[ -n "$_powershell_scripts_zsh_plugin_prefix" ]] || continue
  _powershell_scripts_zsh_plugin_path="$_powershell_scripts_zsh_plugin_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  if [[ -r "$_powershell_scripts_zsh_plugin_path" ]]; then
    if source "$_powershell_scripts_zsh_plugin_path" 2>/dev/null; then
      typeset -g __powershell_scripts_zsh_syntax_highlighting_initialized=1
    fi
    break
  fi
done

unset _powershell_scripts_zsh_plugin_path _powershell_scripts_zsh_plugin_prefix
