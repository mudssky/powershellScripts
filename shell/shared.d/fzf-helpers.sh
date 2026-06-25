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
#        空串则不传 --expect。
#   $3 - extra_opts(可选): fzf 额外参数串，原样追加到 fzf 命令行。
#        用于 --preview / --preview-window 等扩展。由调用方负责引号正确性，
#        底座只做透传，不解析。空串或不传时不追加。
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
#   # 基本用法（两参，旧调用不变）
#   printf 'session-a\nsession-b\n' | fzf_pick_action "[Enter]:attach | [Ctrl-x]:kill" "ctrl-x"
#
#   # 带 preview（三参）
#   printf 'file1\nfile2\n' | fzf_pick_action "[Enter]:编辑" "" \
#     "--preview 'bat {}' --preview-window right:50%"
#
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
  local extra_opts="${3:-}"
  local selection input

  # 缓存 stdin: fzf 对空输入行为不保证（非 tty 下可能挂起等待），
  # 先用 cat 读入，空则直接返回 1，避免进入 fzf 卡住。
  # 调用方通常已自行过滤空列表，此处为底座自身的防御。
  input=$(cat)
  [ -z "$input" ] && return 1

  # 统一组装 fzf 参数：基础项(--height/--reverse/--header) + 条件项。
  # --expect 为空时不传（避免 fzf 报错）；extra_opts 为空时不追加。
  # extra_opts 用 eval 展开，以便正确处理其中嵌套的引号
  # (如 "--preview 'bat {}'"), 否则整串会被当成单个参数。
  # 安全性: extra_opts 来自本仓库的调用方, 非外部输入, eval 风险可控。
  local fzf_args=(--height=40% --reverse --header="$header")
  if [ -n "$expect_keys" ]; then
    fzf_args+=(--expect="$expect_keys")
  fi

  if [ -n "$extra_opts" ]; then
    # shellcheck disable=SC2086  # 故意按词分割展开 extra_opts
    selection=$(printf '%s\n' "$input" | fzf "${fzf_args[@]}" $extra_opts)
  else
    selection=$(printf '%s\n' "$input" | fzf "${fzf_args[@]}")
  fi

  # 用户按 Esc/Ctrl-c → fzf 返回非 0。
  if [ $? -ne 0 ] || [ -z "$selection" ]; then
    return 1
  fi

  # 解析 fzf 输出：
  #   有 --expect 时: 第 1 行 = 按下的 expect 键，Enter 为空行；第 2 行 = 选中条目。
  #   无 --expect 时: fzf 只输出选中条目本身。
  # 用 read 配合「整体块」读取，避免管道子 shell 截断退出码。
  local key line
  if [ -n "$expect_keys" ]; then
    {
      read -r key
      read -r line
    } <<EOF
$selection
EOF
  else
    key=''
    line="$selection"
  fi

  FZF_PICK_ACTION="$key"
  FZF_PICK_ITEM="$line"

  # 极端情况：解析后条目仍空（不应发生），视为未选中。
  if [ -z "$FZF_PICK_ITEM" ]; then
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# fzf_list_action — 「列表→选择→解析→分派」同构命令薄封装
#
# 设计意图:
#   tmux-sessions / zellij-sessions / bluetooth 三个命令结构高度同构,
#   都遵循固定生命周期:
#     取列表 → fzf 选择 → 解析选中行为真实值 → case 分派动作
#   本函数把「空列表提示 / fzf 选择 / 取消处理 / 解析调用」这 4 段样板统一吃掉,
#   调用方只声明: 列表命令、解析器、动作分派器。
#
# 为何用「命令名字符串」而非函数引用:
#   bash/zsh 跨函数边界传函数引用会触发作用域/eval 陷阱,
#   改为传「可执行命令的名字」(parser_cmd 和 action_cmd),
#   底座按名调用, 干净可靠。parser 用现成外部命令(cut/awk),
#   action 用调用方定义的分派函数(_xxx_dispatch)。
#
# 入参:
#   $1 list_cmd     产出候选列表的命令串(如 'tmux list-sessions')。
#                   底座 eval 执行它, 输出每行一个候选(含显示文本)。
#   $2 tag          错误/提示前缀(如 'tmux' → 输出 [tmux] ...)。
#   $3 header       fzf 顶部提示文本(说明按键含义)。
#   $4 parser_cmd   把 FZF_PICK_ITEM 整行解析为「真实值」的命令。
#                   从 stdin 读选中行, stdout 输出真实值(如会话名/MAC)。
#                   例: tmux 用 'cut -d: -f1', bluetooth 用 'cut -f2'(tab分隔)。
#                   该命令需自行可用(外部命令或调用方定义的函数名)。
#   $5 action_cmd   动作分派器函数名。底座调用: $5 "$真实值" "$动作键"。
#                   分派器内部 case 区分 attach/kill 等(见各领域文件示例)。
#   $6 extra_opts   (可选) fzf 额外参数串(如 preview), 透传给 fzf_pick_action。
#
# 返回码:
#   0 - 正常结束(含空列表/取消/缺工具, 均为友好退出)。
#
# 用法示例(tmux-sessions 迁移后):
#   _tmux_dispatch() {
#     case "$2" in
#       ctrl-x) tmux kill-session -t "$1" ;;
#       *) [ -n "$TMUX" ] && tmux switch-client -t "$1" || tmux attach-session -t "$1" ;;
#     esac
#   }
#   tmux-sessions() {
#     command -v tmux >/dev/null 2>&1 || { printf '%s[tmux]%s 未安装\n' ...; return 0; }
#     fzf_list_action 'tmux list-sessions' 'tmux' \
#       '[Enter]:attach | [Ctrl-x]:kill' 'cut -d: -f1' _tmux_dispatch
#   }
# ----------------------------------------------------------------------
fzf_list_action() {
  local list_cmd="${1:-}"
  local tag="${2:-fzf}"
  local header="${3:-}"
  local parser_cmd="${4:-cat}"
  local action_cmd="${5:-}"
  local extra_opts="${6:-}"

  # 守护: fzf/底座 必需(领域工具的守护由调用方在调用前自行处理)。
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s[%s]%s 请先安装 fzf。\n' "$_FZF_HLP_RED" "$tag" "$_FZF_HLP_NC"
    return 0
  fi

  # 取列表。list_cmd 可能含管道(如 blueutil --paired | _bt_parse), 用 eval 展开。
  # 列表为空 → 友好提示并返回(样板 #2 下沉至此)。
  local items
  # shellcheck disable=SC2086  # list_cmd 需按命令展开(含管道)
  items=$(eval "$list_cmd" 2>/dev/null)
  if [ -z "$items" ]; then
    printf '%s[%s]%s 当前没有可选项。\n' "$_FZF_HLP_YELLOW" "$tag" "$_FZF_HLP_NC"
    return 0
  fi

  # 交互选择(样板 #3/#4 下沉至 fzf_pick_action)。
  # 不能用管道调用函数：bash 会在子 shell 执行管道右侧，导致全局回传变量丢失。
  fzf_pick_action "$header" "ctrl-x" "$extra_opts" <<EOF
$items
EOF
  if [ $? -ne 0 ]; then
    return 0  # 用户取消
  fi

  # 解析选中行为真实值(样板 #5 下沉至此: 调用方只声明 parser_cmd, 不手写)。
  local real_value
  real_value=$(printf '%s\n' "$FZF_PICK_ITEM" | eval "$parser_cmd" 2>/dev/null)
  if [ -z "$real_value" ]; then
    printf '%s[%s]%s 无法解析选中项。\n' "$_FZF_HLP_RED" "$tag" "$_FZF_HLP_NC"
    return 0
  fi

  # 动作分派: action_cmd 接收 (真实值, 动作键), 自行 case。
  if [ -n "$action_cmd" ]; then
    "$action_cmd" "$real_value" "$FZF_PICK_ACTION"
  fi
  return 0
}
