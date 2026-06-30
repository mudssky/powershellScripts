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
# 返回码: 透传 zellij 命令退出码。
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
# _zellij_list_sessions — 输出供 fzf 展示的无样式 zellij 会话列表
#
# 设计意图:
#   zellij list-sessions 默认会在 TTY 中输出 ANSI 颜色，若直接 cut 第一列，
#   会把转义码混入会话名，导致 attach 报「会话不存在」。使用 zellij 官方
#   提供的 --no-formatting，既保留创建时间/退出状态等上下文，又避免颜色码
#   污染真实会话名。
#
# 入参: 无。
# 返回值:
#   stdout - 每行一个无 ANSI 样式的 zellij 会话展示行。
# 返回码: 透传 zellij list-sessions 退出码。
# ----------------------------------------------------------------------
_zellij_list_sessions() {
  zellij list-sessions --no-formatting
}

# ----------------------------------------------------------------------
# zellij-sessions — 列出 zellij 会话, 交互式 attach 或 kill
#
# 设计意图:
#   声明式: 只声明「列表命令 + 解析器 + 分派器」。
#   会话列表由 _zellij_list_sessions 产出无样式展示行，parser 去掉状态后缀
#   得到会话名，避免显示文案进入 attach/kill 参数。
#
# 入参: 无。
# 返回码: 0 正常结束(含无会话/工具缺失/取消, 均为友好退出)。
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
