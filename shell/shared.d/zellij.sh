#!/bin/bash
# ========================================================================
# 文件: zellij.sh
# 作用: 基于 fzf 的 zellij 会话交互管理。
#       依赖 fzf-helpers.sh 提供的 fzf_list_action 薄封装。
#       本文件由 deploy.sh 软链接到 ~/.bashrc.d/，bash 与 zsh 都会 source。
# ========================================================================

# ----------------------------------------------------------------------
# _zellij_dispatch — zellij 动作分派器
#
# 设计意图:
#   fzf_list_action 解析出真实会话名后回调本函数, case 分派 attach/kill。
#   集中 zellij 领域知识于此。
#
# 入参:
#   $1 - 会话名(已解析)。
#   $2 - 动作键: 'ctrl-x' = kill, 空 = attach。
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

# ----------------------------------------------------------------------
# zellij-sessions — 列出 zellij 会话, 交互式 attach 或 kill
#
# 设计意图:
#   声明式: 只声明「列表命令 + 解析器 + 分派器」。
#   zellij list-sessions 输出形如 "dev [ExitStatus: 0]"; 用 cut -d' ' -f1 取会话名。
#
# 入参: 无。返回码: 0 正常结束。
# ----------------------------------------------------------------------
zellij-sessions() {
  if ! command -v zellij >/dev/null 2>&1; then
    printf '%s[zellij]%s 未检测到 zellij，请先安装。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi
  fzf_list_action 'zellij list-sessions' 'zellij' \
    '[Enter]:attach | [Ctrl-x]:kill session' \
    "cut -d' ' -f1" _zellij_dispatch
}
