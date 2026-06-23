#!/bin/bash
# ========================================================================
# 文件: zellij.sh
# 作用: 基于 fzf 的 zellij 会话交互管理。
#       依赖 fzf-helpers.sh 提供的 fzf_pick_action 底座。
#       本文件由 deploy.sh 软链接到 ~/.bashrc.d/，bash 与 zsh 都会 source。
#
# 加载顺序说明:
#   函数定义为惰性，本文件只定义 zellij-sessions 函数；
#   工具存在性检查放在「函数体内」运行时执行，而非文件顶层，
#   确保函数恒被定义（与 tmux.sh 同理）。
# ========================================================================

# ----------------------------------------------------------------------
# zellij-sessions — 列出 zellij 会话，交互式 attach 或 kill
#
# 设计意图:
#   用 fzf 列出所有 zellij 会话，用户选中后:
#     Enter   → attach 到选中会话
#     Ctrl-x  → kill 选中的会话
#   与 tmux-sessions 保持一致的交互范式（同一底座、同一按键语义）。
#
# 入参: 无。
#
# 返回码:
#   0 - 正常结束（含无会话/工具缺失/用户取消，均为友好退出）。
#
# 健壮性:
#   - zellij/fzf/底座缺失 → 提示并返回 0。
#   - 无活动会话 → 提示并返回 0。
#   - zellij 子命令版本差异: kill-session 为 zellij ≥0.40 命名；
#     旧版可能用 delete-session，这里优先 kill-session，失败时降级提示。
# ----------------------------------------------------------------------
zellij-sessions() {
  # 运行时检查 zellij（不放在文件顶层，确保函数恒被定义）。
  if ! command -v zellij >/dev/null 2>&1; then
    printf '%s[zellij]%s 未检测到 zellij，请先安装。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s[zellij]%s 请先安装 fzf。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi
  if ! command -v fzf_pick_action >/dev/null 2>&1; then
    printf '%s[zellij]%s 底座 fzf-helpers.sh 未加载，请检查部署。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi

  # 读取会话列表。
  # zellij list-sessions 输出形如:
  #   dev [ExitStatus: 0]
  #   main (EXITED)
  #   tmp [ExitStatus: 0] (current)
  # 每行首个空白字段为真实会话名，后续为状态标记。
  local sessions
  sessions=$(zellij list-sessions 2>/dev/null)
  if [ -z "$sessions" ]; then
    printf '%s[zellij]%s 当前没有活动会话。\n' "$_FZF_HLP_YELLOW" "$_FZF_HLP_NC"
    return 0
  fi

  # 整行作为显示行交给 fzf。
  printf '%s\n' "$sessions" | fzf_pick_action \
    '[Enter]:attach | [Ctrl-x]:kill session'

  if [ $? -ne 0 ]; then
    # 用户取消。
    return 0
  fi

  # 提取真实会话名：取首个空白之前的部分。
  # 用参数扩展 ${FZF_PICK_ITEM%% *} 切，兼容 bash/zsh。
  local session_name
  session_name="${FZF_PICK_ITEM%% *}"

  if [ -z "$session_name" ]; then
    printf '%s[zellij]%s 无法解析会话名。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi

  case "$FZF_PICK_ACTION" in
    ctrl-x)
      # kill 会话：zellij ≥0.40 用 kill-session。
      # 旧版可能无此子命令，失败时给出版本提示。
      if zellij kill-session "$session_name" 2>/dev/null; then
        printf '%s[zellij]%s 已删除会话: %s\n' "$_FZF_HLP_GREEN" "$_FZF_HLP_NC" "$session_name"
      else
        printf '%s[zellij]%s 删除失败，请检查 zellij 版本（需 ≥0.40 的 kill-session）: %s\n' \
          "$_FZF_HLP_RED" "$_FZF_HLP_NC" "$session_name"
      fi
      ;;
    *)
      # 默认动作 = attach。zellij attach 不允许在已有 zellij 内嵌套 attach，
      # 会自行报错；此处直接透传由 zellij 处理。
      zellij attach "$session_name"
      ;;
  esac
}
