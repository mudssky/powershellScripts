#!/bin/bash
# ========================================================================
# 文件: tmux.sh
# 作用: 基于 fzf 的 tmux 会话交互管理。
#       依赖 fzf-helpers.sh 提供的 fzf_pick_action 底座。
#       本文件由 deploy.sh 软链接到 ~/.bashrc.d/，bash 与 zsh 都会 source。
#
# 加载顺序说明:
#   函数定义为惰性，本文件只定义 tmux-sessions 函数；
#   工具存在性检查放在「函数体内」运行时执行，而非文件顶层。
#   这样即便 tmux 未安装，函数仍被定义，调用时得到友好提示而非
#   'command not found'。详见下方函数注释。
# ========================================================================

# ----------------------------------------------------------------------
# tmux-sessions — 列出 tmux 会话，交互式 attach 或 kill
#
# 设计意图:
#   用 fzf 列出所有 tmux 会话，用户选中后:
#     Enter   → 在当前 shell attach（接管当前终端，退出后回原 shell）
#     Ctrl-x  → kill 选中的会话
#   复用 fzf_pick_action 底座，与 fzf-history 的 --expect 多动作范式一致。
#
# 入参: 无。
#
# 返回码:
#   0 - 正常结束（含无会话/工具缺失/用户取消，均为友好退出）。
#
# 健壮性（守护放在函数体内，而非文件顶层）:
#   - tmux/fzf/底座缺失 → 提示并返回 0，而非函数未定义导致 command not found。
#   - 无活动会话 → 提示并返回 0。
#   - attach 在当前 shell 执行，保证退出 tmux 后回到原 shell（不用 exec 替换进程）。
# ----------------------------------------------------------------------
tmux-sessions() {
  # 运行时检查 tmux（不放在文件顶层，确保函数恒被定义）。
  if ! command -v tmux >/dev/null 2>&1; then
    printf '%s[tmux]%s 未检测到 tmux，请先安装。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi
  # fzf 与底座缺失给出明确提示。
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s[tmux]%s 请先安装 fzf。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi
  if ! command -v fzf_pick_action >/dev/null 2>&1; then
    printf '%s[tmux]%s 底座 fzf-helpers.sh 未加载，请检查部署。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi

  # 读取会话列表。
  #   无运行中的 server 时 tmux list-sessions 退出码非 0（输出 'no server running'），
  #   此时视为「无活动会话」而非错误。
  local sessions
  sessions=$(tmux list-sessions 2>/dev/null)
  if [ -z "$sessions" ]; then
    printf '%s[tmux]%s 当前没有活动会话。\n' "$_FZF_HLP_YELLOW" "$_FZF_HLP_NC"
    return 0
  fi

  # list-sessions 默认输出形如:
  #   dev: 3 windows (created ...) (attached)
  #   main: 1 windows (created ...) (detached)
  # 整行作为显示行，按 : 前缀切出真实会话名。
  printf '%s\n' "$sessions" | fzf_pick_action \
    '[Enter]:attach | [Ctrl-x]:kill session'

  if [ $? -ne 0 ]; then
    # 用户按 Esc/Ctrl-c 取消。
    return 0
  fi

  # 从显示行提取真实会话名：取首个 ':' 之前的部分。
  # ${FZF_PICK_ITEM%%:*} 为参数扩展（非正则），bash/zsh 均支持。
  local session_name
  session_name="${FZF_PICK_ITEM%%:*}"

  if [ -z "$session_name" ]; then
    printf '%s[tmux]%s 无法解析会话名。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi

  case "$FZF_PICK_ACTION" in
    ctrl-x)
      # kill 会话：-t 指定目标。
      if tmux kill-session -t "$session_name" 2>/dev/null; then
        printf '%s[tmux]%s 已删除会话: %s\n' "$_FZF_HLP_GREEN" "$_FZF_HLP_NC" "$session_name"
      else
        printf '%s[tmux]%s 删除会话失败: %s\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC" "$session_name"
      fi
      ;;
    *)
      # 默认动作 = attach。在当前 shell 执行，不用 exec（退出 tmux 后回原 shell）。
      # 若当前已在 tmux 内（$TMUX 非空），attach 会失败，改用 switch-client 切换。
      if [ -n "$TMUX" ]; then
        tmux switch-client -t "$session_name"
      else
        tmux attach-session -t "$session_name"
      fi
      ;;
  esac
}
