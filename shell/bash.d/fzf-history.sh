#!/bin/bash
# ======================================================================
# 文件：fzf-history.sh
# 作用：提供 Bash 的 fzf 历史检索 widget，并绑定 Alt+h。
# 兼容性：仅 Bash 交互式 shell。
# ======================================================================

# -- history widget -----------------------------------------------------
if [[ -n "$BASH_VERSION" ]] && command -v fzf >/dev/null 2>&1; then
  # ----------------------------------------------------------------------
  # __fzf_history_smart_widget — 选择历史命令并放回、执行或复制。
  #
  # 参数：无。
  # 副作用：修改 Readline 缓冲区，或执行命令、写入系统剪贴板。
  # 返回码：Readline widget 的执行状态；取消选择时提前返回。
  # ----------------------------------------------------------------------
  __fzf_history_smart_widget() {
    # 统一读当前 shell 的历史，并按最近优先去重。
    local selected
    selected=$(history | sed 's/^ *[0-9]\+[* ]*//' | tac | awk '!seen[$0]++' | \
      fzf --no-sort --height=40% --reverse \
        --bind 'enter:accept' \
        --bind 'ctrl-e:accept' \
        --bind 'ctrl-y:accept' \
        --expect=ctrl-e,ctrl-y \
        --header='[Enter]:放入命令行 | [Ctrl-E]:立即执行 | [Ctrl-Y]:复制到剪贴板')

    [[ -z "$selected" ]] && return

    local key
    local cmd

    key=$(printf '%s\n' "$selected" | sed -n '1p')
    cmd=$(printf '%s\n' "$selected" | sed -n '2p')

    # Enter 不返回 expect 行，因此将第一行当作命令。
    if [[ -z "$cmd" ]]; then
      cmd="$key"
      key=''
    fi

    [[ -z "$cmd" ]] && return

    case "$key" in
      ctrl-e)
        READLINE_LINE="$cmd"
        READLINE_POINT=${#READLINE_LINE}
        printf '\n[Running]: %s\n' "$cmd"
        eval "$cmd"
        READLINE_LINE=''
        READLINE_POINT=0
        ;;
      ctrl-y)
        if command -v wl-copy >/dev/null 2>&1; then
          printf '%s' "$cmd" | wl-copy
          printf '\n[Copied to clipboard]\n'
        elif command -v xclip >/dev/null 2>&1; then
          printf '%s' "$cmd" | xclip -selection clipboard
          printf '\n[Copied to clipboard]\n'
        elif command -v xsel >/dev/null 2>&1; then
          printf '%s' "$cmd" | xsel --clipboard --input
          printf '\n[Copied to clipboard]\n'
        elif command -v pbcopy >/dev/null 2>&1; then
          printf '%s' "$cmd" | pbcopy
          printf '\n[Copied to clipboard]\n'
        else
          printf '\n[No clipboard tool found: need wl-copy/xclip/xsel/pbcopy]\n'
        fi
        ;;
      *)
        READLINE_LINE="$cmd"
        READLINE_POINT=${#READLINE_LINE}
        ;;
    esac
  }

  bind -x '"\eh":__fzf_history_smart_widget'
fi
