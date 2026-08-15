#!/bin/bash
# ======================================================================
# 文件：tmux.sh
# 作用：提供基于 fzf 的 tmux 会话交互管理。
# 兼容性：Bash / Zsh；依赖 fzf-helpers.sh。
# 加载方式：工具守护位于函数体内，函数定义不依赖加载顺序。
# ======================================================================

# ----------------------------------------------------------------------
# _tmux_dispatch — 分派 tmux 会话 attach 或 kill 动作。
#
# 设计意图：集中 tmux 领域动作，使 fzf_list_action 保持通用。
#
# 参数：$1 — 已解析的会话名；$2 — 动作键，ctrl-x 为 kill，其它为 attach。
# 输出：stdout — 删除成功或失败提示。
# 返回码：透传 tmux 命令退出码。
# ----------------------------------------------------------------------
_tmux_dispatch() {
  local session="$1"
  local action="$2"
  case "$action" in
    ctrl-x)
      # kill 会话。
      if tmux kill-session -t "$session" 2>/dev/null; then
        printf '%s[tmux]%s 已删除会话: %s\n' "$_FZF_HLP_GREEN" "$_FZF_HLP_NC" "$session"
      else
        printf '%s[tmux]%s 删除会话失败: %s\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC" "$session"
      fi
      ;;
    *)
      # 默认动作 = attach。当前 shell 执行, 不用 exec(退出 tmux 后回原 shell)。
      # 若当前已在 tmux 内($TMUX 非空), attach 会失败, 改用 switch-client 切换。
      if [ -n "$TMUX" ]; then
        tmux switch-client -t "$session"
      else
        tmux attach-session -t "$session"
      fi
      ;;
  esac
}

# _tmux_list_sessions — 输出供 fzf 展示的稳定 tmux 会话列表。
# 参数：无。
# 输出：stdout — tab 分隔的会话名、窗口数、附着状态和创建时间。
# 返回码：透传 tmux list-sessions 退出码。
_tmux_list_sessions() {
  tmux list-sessions -F '#{session_name}	#{session_windows} windows	#{?session_attached,attached,detached}	#{session_created_string}'
}

# ----------------------------------------------------------------------
# tmux-sessions — 交互式 attach 或 kill tmux 会话。
#
# 设计意图：由 fzf_list_action 统一处理空列表、取消、选择与解析；Ctrl-x 删除后
# 刷新列表继续选择，Enter attach 后结束选择流程。
#
# 参数：无。
# 返回码：0 — 正常结束，包括无会话、工具缺失或取消。
# ----------------------------------------------------------------------
tmux-sessions() {
  # 工具守护放在函数体内，确保函数恒被定义。
  if ! command -v tmux >/dev/null 2>&1; then
    printf '%s[tmux]%s 未检测到 tmux，请先安装。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi
  # 第一列固定为真实会话名，后续列只用于展示；无 server 时由底座处理空输出。
  fzf_list_action '_tmux_list_sessions' 'tmux' \
    '[Enter]:attach | [Ctrl-x]:kill session' \
    'cut -f1' _tmux_dispatch '' 'ctrl-x'
}
