#!/bin/bash
# ========================================================================
# 文件: tmux.sh
# 作用: 基于 fzf 的 tmux 会话交互管理。
#       依赖 fzf-helpers.sh 提供的 fzf_list_action 薄封装。
#       本文件由 deploy.sh 软链接到 ~/.bashrc.d/，bash 与 zsh 都会 source。
#
# 加载顺序说明:
#   函数定义为惰性，本文件只定义 tmux-sessions 与分派器；
#   工具存在性检查放在「函数体内」运行时执行，确保函数恒被定义。
# ========================================================================

# ----------------------------------------------------------------------
# _tmux_dispatch — tmux 动作分派器
#
# 设计意图:
#   fzf_list_action 解析出真实会话名后回调本函数, 由它 case 分派具体动作。
#   集中 tmux 领域知识于此, 与底座的通用选择逻辑解耦。
#
# 入参:
#   $1 - 会话名(已从显示行解析出真实值)。
#   $2 - 动作键: 'ctrl-x' = kill, 空 = attach。
# 返回码: 透传 tmux 命令退出码。
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

# ----------------------------------------------------------------------
# tmux-sessions — 列出 tmux 会话, 交互式 attach 或 kill
#
# 设计意图:
#   声明式: 只声明「列表命令 + 解析器 + 分派器」, 其余(空列表提示/取消/
#   fzf 选择/选中行解析)由 fzf_list_action 统一处理。Ctrl-x 删除后刷新列表
#   继续停留, 便于连续清理会话；Enter attach 后退出选择流程。
#
# 入参: 无。
# 返回码: 0 正常结束(含无会话/工具缺失/取消, 均为友好退出)。
# ----------------------------------------------------------------------
tmux-sessions() {
  # 运行时检查 tmux(放函数体内, 确保函数恒被定义)。
  if ! command -v tmux >/dev/null 2>&1; then
    printf '%s[tmux]%s 未检测到 tmux，请先安装。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi
  # list-sessions 输出形如 "dev: 3 windows (attached)"; 用 cut -d: -f1 取会话名。
  # 无 server 时 tmux list-sessions 退出码非0, fzf_list_action 捕获空输出后提示。
  fzf_list_action 'tmux list-sessions' 'tmux' \
    '[Enter]:attach | [Ctrl-x]:kill session' \
    'cut -d: -f1' _tmux_dispatch '' 'ctrl-x'
}
