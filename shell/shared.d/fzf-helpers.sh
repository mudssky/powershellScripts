#!/bin/bash
# ========================================================================
# 文件: fzf-helpers.sh
# 作用: 提供基于 fzf 的通用交互底座函数，供 tmux.sh / zellij.sh 等场景复用。
#       本文件由 deploy.sh 软链接到 ~/.bashrc.d/，bash 与 zsh 都会 source，
#       因此必须双 shell 兼容，禁用 zle / bind -x 等 shell 专属结构。
#
# 加载顺序说明:
#   bash/zsh 函数定义为惰性——本文件定义 fzf_pick_action 时，
#   领域文件 tmux.sh/zellij.sh 只需「定义」自己的函数，
#   函数体内对 fzf_pick_action 的引用在「调用时」才解析。
#   故无需保证 *.sh 的 glob 加载顺序，只要全部 source 完即可。
# ========================================================================

# ----------------------------------------------------------------------
# 统一的颜色/提示输出（与 deploy.sh 风格一致，仅交互式场景使用）
# 放在文件级，避免每次调用都重新定义。
# ----------------------------------------------------------------------
__fzf_helpers_color_setup() {
  # 仅当终端支持颜色时启用 ANSI 转义，否则置空避免乱码。
  if [ -t 1 ] && [ -n "$TERM" ] && [ "$TERM" != "dumb" ]; then
    _FZF_HLP_RED=$'\033[0;31m'
    _FZF_HLP_GREEN=$'\033[0;32m'
    _FZF_HLP_YELLOW=$'\033[1;33m'
    _FZF_HLP_CYAN=$'\033[0;36m'
    _FZF_HLP_NC=$'\033[0m'
  else
    _FZF_HLP_RED=''
    _FZF_HLP_GREEN=''
    _FZF_HLP_YELLOW=''
    _FZF_HLP_CYAN=''
    _FZF_HLP_NC=''
  fi
}
__fzf_helpers_color_setup

# ----------------------------------------------------------------------
# fzf_pick_action — fzf 通用「选条目 + 选动作」底座
#
# 设计意图:
#   attach 这类操作必须在「当前 shell 进程」执行（要接管当前终端），
#   若用 item=$(fzf_pick_action ...) 子 shell 回传，attach 会发生在子 shell、
#   退出即丢终端。因此本函数通过「全局变量」回传两项结果，调用方在当前
#   shell 读取后直接执行目标命令。此语义与 fzf-history 用 BUFFER/READLINE_LINE
#   在当前 shell 写命令行同源。
#
# 入参:
#   $1 - header: fzf 顶部提示文本（说明各按键含义）。
#   $2 - expect_keys: --expect 的按键，逗号分隔，如 "ctrl-x,ctrl-d"。
#        Enter 固定走 accept 语义（表示默认动作），不在 expect 列表中。
#
# 输入(stdin):
#   候选条目，每行一个，已包含最终显示文本（调用方负责拼好显示格式）。
#   调用方需自行从整行解析出真实值（如会话名），本函数保持中立。
#
# 回传(全局变量，调用方在函数返回后立即读取):
#   FZF_PICK_ITEM   - 用户选中的整行原文；无选中时为空。
#   FZF_PICK_ACTION - 用户按下的 expect 键名（如 "ctrl-x"）；按 Enter 时为空串。
#
# 返回码:
#   0 - 用户正常选中条目。
#   1 - fzf 不可用、stdin 为空、或用户未选中（Esc/Ctrl-c）。
#
# 用法示例:
#   printf 'session-a\nsession-b\n' | fzf_pick_action "[Enter]:attach | [Ctrl-x]:kill" "ctrl-x"
#   if [ $? -eq 0 ]; then
#     case "$FZF_PICK_ACTION" in
#       ctrl-x) tmux kill-session -t "$FZF_PICK_ITEM" ;;
#       *)      tmux attach-session -t "$FZF_PICK_ITEM" ;;
#     esac
#   fi
# ----------------------------------------------------------------------
fzf_pick_action() {
  # 每次调用前清空上一次的回传变量，避免脏数据。
  FZF_PICK_ITEM=''
  FZF_PICK_ACTION=''

  # fzf 未安装则静默失败，交由调用方提示。
  if ! command -v fzf >/dev/null 2>&1; then
    return 1
  fi

  local header="${1:-}"
  local expect_keys="${2:-}"
  local selection input

  # 缓存 stdin: fzf 对空输入行为不保证（非 tty 下可能挂起等待），
  # 先用 cat 读入，空则直接返回 1，避免进入 fzf 卡住。
  # 调用方通常已自行过滤空列表，此处为底座自身的防御。
  input=$(cat)
  [ -z "$input" ] && return 1

  # 组装 fzf 参数：--expect 为空时不传该 flag（避免 fzf 报错）。
  # --height=40% --reverse 与 fzf-history 保持一致观感。
  if [ -n "$expect_keys" ]; then
    selection=$(printf '%s\n' "$input" | fzf --height=40% --reverse \
      --header="$header" \
      --expect="$expect_keys")
  else
    selection=$(printf '%s\n' "$input" | fzf --height=40% --reverse \
      --header="$header")
  fi

  # 用户按 Esc/Ctrl-c → fzf 返回非 0。
  if [ $? -ne 0 ] || [ -z "$selection" ]; then
    return 1
  fi

  # 解析 fzf --expect 输出：
  #   第 1 行 = 按下的 expect 键（按 Enter 时为空行）
  #   第 2 行起 = 选中的条目
  # 用 read 配合「整体块」读取，避免管道子 shell 截断退出码。
  local key line
  {
    read -r key
    read -r line
  } <<EOF
$selection
EOF

  # 未按 expect 键时 fzf 第一行是空，第二行才是条目。
  FZF_PICK_ACTION="$key"
  FZF_PICK_ITEM="$line"

  # 极端情况：解析后条目仍空（不应发生），视为未选中。
  if [ -z "$FZF_PICK_ITEM" ]; then
    return 1
  fi
  return 0
}
