#!/bin/bash
# ======================================================================
# 文件：zellij.sh
# 作用：提供基于 fzf 的 zellij 会话交互管理。
# 兼容性：Bash / Zsh；依赖 fzf-helpers.sh。
# ======================================================================

# ----------------------------------------------------------------------
# _zellij_dispatch — 分派 zellij 会话 attach 或 kill 动作。
# 参数：$1 — 已解析的会话名；$2 — 动作键，ctrl-x 为 kill，其它为 attach。
# 输出：stdout — 删除成功或失败提示。
# 返回码：透传 zellij 命令退出码。
# ----------------------------------------------------------------------
_zellij_dispatch() {
  local session="$1"
  local action="$2"
  case "$action" in
    ctrl-x)
      # kill 会话: zellij ≥0.40 用 kill-session, 旧版失败时给出版本提示。
      if zellij kill-session "$session" 2>/dev/null; then
        printf '%s[zellij]%s 已删除会话: %s\n' "$_FZF_HLP_GREEN" "$_FZF_HLP_NC" "$session"
      else
        printf '%s[zellij]%s 删除失败，请检查 zellij 版本（需 ≥0.40 的 kill-session）: %s\n' \
          "$_FZF_HLP_RED" "$_FZF_HLP_NC" "$session"
      fi
      ;;
    *)
      # 默认动作 = attach。zellij attach 不允许在已有 zellij 内嵌套 attach,
      # 会自行报错; 此处直接透传由 zellij 处理。
      zellij attach "$session"
      ;;
  esac
}

# _zellij_list_sessions — 输出供 fzf 展示的无样式 zellij 会话列表。
# 参数：无。
# 输出：stdout — 每行一个无 ANSI 样式的 zellij 会话展示行。
# 返回码：透传 zellij list-sessions 退出码。
_zellij_list_sessions() {
  zellij list-sessions --no-formatting
}

# ----------------------------------------------------------------------
# zellij-sessions — 交互式 attach 或 kill zellij 会话。
#
# 设计意图：使用 --no-formatting 避免 ANSI 转义码污染真实会话名，再由 parser
# 去除状态后缀后交给分派器。
#
# 参数：无。
# 返回码：0 — 正常结束，包括无会话、工具缺失或取消。
# ----------------------------------------------------------------------
zellij-sessions() {
  if ! command -v zellij >/dev/null 2>&1; then
    printf '%s[zellij]%s 未检测到 zellij，请先安装。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi
  fzf_list_action '_zellij_list_sessions' 'zellij' \
    '[Enter]:attach | [Ctrl-x]:kill session' \
    "sed 's/ \\[Created.*//'" _zellij_dispatch
}
