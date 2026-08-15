#!/bin/bash
# ======================================================================
# 文件：fzf-helpers.sh
# 作用：提供基于 fzf 的通用交互底座函数，供会话、设备和文件命令复用。
# 兼容性：Bash / Zsh；本文件与领域片段均由 deploy.sh source。
# 加载方式：函数惰性解析，不依赖 *.sh glob 加载顺序。
# ======================================================================

# -- helper state -------------------------------------------------------
# __fzf_helpers_color_setup — 初始化交互提示使用的颜色变量。
# 参数：无。
# 副作用：设置 _FZF_HLP_* 全局变量。
# 返回码：始终返回 0。
__fzf_helpers_color_setup() {
  # 仅当终端支持颜色时启用 ANSI，避免非 TTY 输出乱码。
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
# fzf_pick_action — 从 stdin 读取候选，并使用 fzf 完成“选条目 + 选动作”。
#
# 设计意图：结果通过全局变量回传，确保 attach 等动作仍在当前 shell 执行，不被
# 命令替换或管道子 shell 吞掉终端状态。
#
# 参数：
#   $1 — header；$2 — expect 按键列表；$3 — 可选 fzf 参数串。
# 副作用：读取 stdin，并设置 FZF_PICK_ITEM 与 FZF_PICK_ACTION 全局变量。
# 返回码：0 — 正常选中；1 — fzf 不可用、输入为空或用户取消。
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

  # 缓存 stdin：fzf 对空输入行为不保证（非 TTY 下可能挂起等待），先用 cat
  # 读入，空则直接返回 1，避免进入 fzf 卡住。调用方通常已自行过滤空列表，
  # 此处为底座自身的防御。
  input=$(cat)
  [ -z "$input" ] && return 1

  # 统一组装 fzf 参数：基础项（--height/--reverse/--header）与条件项。
  # --expect 为空时不传，避免 fzf 报错；extra_opts 为空时不追加。
  # extra_opts 用 eval 解析为当前函数的位置参数，以便正确处理其中嵌套的引号
  # （如 "--preview 'bat {}'"），否则整串会被当成单个参数或被普通词分割拆坏。
  # extra_opts 来自本仓库调用方而非外部输入，因此 eval 风险可控。
  local fzf_args=(--height=40% --reverse --header="$header")
  if [ -n "$expect_keys" ]; then
    fzf_args+=(--expect="$expect_keys")
  fi

  if [ -n "$extra_opts" ]; then
    eval "set -- $extra_opts"
    selection=$(printf '%s\n' "$input" | fzf "${fzf_args[@]}" "$@")
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
# fzf_list_action — 统一处理“列表→选择→解析→分派”交互生命周期。
#
# 设计意图：将空列表提示、fzf 选择、取消处理和真实值解析集中到底座，调用方只
# 提供列表命令、解析器与动作分派器；命令名字符串保持 Bash/Zsh 边界稳定。
#
# 参数：
#   $1 — list_cmd；$2 — tag；$3 — header；$4 — parser_cmd；$5 — action_cmd。
#   $6 — 可选 extra_opts；$7 — 可选 repeat_actions。
# 返回码：0 — 正常结束，包括空列表、取消或缺少 fzf。
# ----------------------------------------------------------------------
fzf_list_action() {
  local list_cmd="${1:-}"
  local tag="${2:-fzf}"
  local header="${3:-}"
  local parser_cmd="${4:-cat}"
  local action_cmd="${5:-}"
  local extra_opts="${6:-}"
  local repeat_actions="${7:-}"

  # fzf 是底座必需工具；领域工具由调用方在进入底座前守护。
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s[%s]%s 请先安装 fzf。\n' "$_FZF_HLP_RED" "$tag" "$_FZF_HLP_NC"
    return 0
  fi

  while :; do
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

    # 管理动作执行后可刷新列表继续选择；默认动作(Enter)保持执行后退出。
    if [ -n "$FZF_PICK_ACTION" ]; then
      case ",$repeat_actions," in
        *,"$FZF_PICK_ACTION",*) continue ;;
      esac
    fi
    return 0
  done
  return 0
}
