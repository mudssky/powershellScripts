#!/bin/zsh
# ======================================================================
# 文件：fzf-history.zsh
# 作用：提供 Zsh 的 fzf 历史检索 widget，并绑定 Alt+h。
# 兼容性：仅 Zsh 交互式 shell。
# ======================================================================

# -- history widget -----------------------------------------------------
if [[ -n "$ZSH_VERSION" ]] && command -v fzf >/dev/null 2>&1; then
  # ----------------------------------------------------------------------
  # __fzf_history_smart_widget — 选择历史命令并放回、执行或复制。
  #
  # 参数：无。
  # 副作用：修改 ZLE 缓冲区，或执行命令、写入系统剪贴板。
  # 返回码：ZLE widget 的执行状态；取消选择时刷新命令行并返回。
  # ----------------------------------------------------------------------
  __fzf_history_smart_widget() {
    # 读取 Zsh 历史并按最近优先去重。
    local selected
    selected=$(fc -l 1 | sed 's/^ *[0-9]*[* ]*//' | tac | awk '!seen[$0]++' | \
      fzf --no-sort --height=40% --reverse \
        --bind 'enter:accept' \
        --bind 'ctrl-e:accept' \
        --bind 'ctrl-y:accept' \
        --expect=ctrl-e,ctrl-y \
        --header='[Enter]:放入命令行 | [Ctrl-E]:立即执行 | [Ctrl-Y]:复制到剪贴板')

    [[ -z "$selected" ]] && { zle redisplay; return; }

    local key cmd

    key=$(printf '%s\n' "$selected" | sed -n '1p')
    cmd=$(printf '%s\n' "$selected" | sed -n '2p')

    # Enter 不返回 expect 行，因此将第一行当作命令。
    if [[ -z "$cmd" ]]; then
      cmd="$key"
      key=''
    fi

    [[ -z "$cmd" ]] && { zle redisplay; return; }

    case "$key" in
      ctrl-e)
        BUFFER="$cmd"
        zle accept-line
        ;;
      ctrl-y)
        if command -v pbcopy >/dev/null 2>&1; then
          printf '%s' "$cmd" | pbcopy
          zle -M "[Copied to clipboard]"
        elif command -v wl-copy >/dev/null 2>&1; then
          printf '%s' "$cmd" | wl-copy
          zle -M "[Copied to clipboard]"
        elif command -v xclip >/dev/null 2>&1; then
          printf '%s' "$cmd" | xclip -selection clipboard
          zle -M "[Copied to clipboard]"
        elif command -v xsel >/dev/null 2>&1; then
          printf '%s' "$cmd" | xsel --clipboard --input
          zle -M "[Copied to clipboard]"
        else
          zle -M "[No clipboard tool found: need pbcopy/wl-copy/xclip/xsel]"
        fi
        ;;
      *)
        BUFFER="$cmd"
        CURSOR=${#BUFFER}
        ;;
    esac
    zle redisplay
  }

  zle -N __fzf_history_smart_widget
  bindkey '\eh' __fzf_history_smart_widget
fi
