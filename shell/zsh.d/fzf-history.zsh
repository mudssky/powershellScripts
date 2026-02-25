#!/bin/zsh

# fzf 智能历史检索（Zsh）
# 快捷键: Alt+h
# 功能:
# - Enter  : 放入命令行（不立即执行）
# - Ctrl-e : 立即执行
# - Ctrl-y : 复制到剪贴板

if [[ -n "$ZSH_VERSION" ]] && command -v fzf >/dev/null 2>&1; then
  __fzf_history_smart_widget() {
    # 读取 Zsh 历史并按最近优先去重
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

    # 未按 expect 键时，fzf 只返回一行（即命令本身）
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
