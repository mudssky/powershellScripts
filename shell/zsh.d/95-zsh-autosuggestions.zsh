# ======================================================================
# 文件：95-zsh-autosuggestions.zsh
# 作用：在 Atuin widget 注册后加载 zsh-autosuggestions 插件。
# 兼容性：仅 Zsh 交互式 shell；保留 Ctrl+r 与 Up 键合同。
# ======================================================================

# -- plugin guard -------------------------------------------------------
if [[ -z ${ZSH_VERSION:-} || ! -o interactive ]]; then
  return 0
fi

if [[ ${__powershell_scripts_zsh_autosuggestions_initialized:-0} == 1 ]]; then
  return 0
fi
if (( ${+functions[_zsh_autosuggest_start]} )); then
  typeset -g __powershell_scripts_zsh_autosuggestions_initialized=1
  return 0
fi

# -- plugin discovery ---------------------------------------------------
for _powershell_scripts_zsh_plugin_prefix in \
  "${POWERSHELL_SCRIPTS_HOMEBREW_PREFIX:-}" \
  "${HOMEBREW_PREFIX:-}" \
  /opt/homebrew \
  /usr/local; do
  [[ -n "$_powershell_scripts_zsh_plugin_prefix" ]] || continue
  _powershell_scripts_zsh_plugin_path="$_powershell_scripts_zsh_plugin_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  if [[ -r "$_powershell_scripts_zsh_plugin_path" ]]; then
    if source "$_powershell_scripts_zsh_plugin_path" 2>/dev/null; then
      typeset -g __powershell_scripts_zsh_autosuggestions_initialized=1
    fi
    break
  fi
done

unset _powershell_scripts_zsh_plugin_path _powershell_scripts_zsh_plugin_prefix
