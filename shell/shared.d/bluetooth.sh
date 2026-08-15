#!/bin/bash
# ======================================================================
# 文件：bluetooth.sh
# 作用：基于 fzf 的 macOS blueutil 蓝牙设备交互管理。
# 兼容性：仅 macOS；Bash / Zsh；依赖 fzf-helpers.sh。
# ======================================================================

# ----------------------------------------------------------------------
# _bt_parse_device — 将 stdin 中的 blueutil 单行输出解析为地址与名称。
# 参数：无。
# 输出：stdout — 地址<TAB>名称，每行一个设备。
# 返回码：sed 的退出码。
# ----------------------------------------------------------------------
_bt_parse_device() {
  sed -nE \
    -e 's/^address: ([^,]+),.*name: "([^"]*)".*/\1\t\2/p' \
    -e 's/^address: ([^,]+),.*$/\1\t(unnamed)/p'
}

# ----------------------------------------------------------------------
# _bt_build_display — 生成显示行与真实地址列表。
#
# 设计意图：逐设备查询连接状态，使用 tab 将展示文本与真实地址分开，避免文案
# 进入连接或断开参数。
#
# 参数：无。
# 输出：stdout — 显示行<TAB>地址，每行一个已配对设备。
# 返回码：blueutil 查询链的退出码。
# ----------------------------------------------------------------------
_bt_build_display() {
  local addr name state
  # 逐行解析配对设备，并补充连接状态前缀。
  while IFS=$'\t' read -r addr name; do
    [ -z "$addr" ] && continue
    if blueutil --is-connected "$addr" >/dev/null 2>&1; then
      state='[✓已连]'
    else
      state='[ 未连]'
    fi
    printf '%s %s (%s)\t%s\n' "$state" "$name" "$addr" "$addr"
  done <<EOF
$(blueutil --paired 2>/dev/null | _bt_parse_device)
EOF
}

# _bluetooth_dispatch — 分派蓝牙设备连接或断开动作。
# 参数：$1 — 已解析的设备地址；$2 — 动作键，ctrl-x 为断开，其它为连接。
# 输出：stdout — 操作成功或失败提示。
# 返回码：blueutil 操作退出码。
_bluetooth_dispatch() {
  local addr="$1"
  local action="$2"
  case "$action" in
    ctrl-x)
      if blueutil --disconnect "$addr" 2>/dev/null; then
        printf '%s[bt]%s 已断开: %s\n' "$_FZF_HLP_GREEN" "$_FZF_HLP_NC" "$addr"
      else
        printf '%s[bt]%s 断开失败（设备可能未连接）: %s\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC" "$addr"
      fi
      ;;
    *)
      if blueutil --connect "$addr" 2>/dev/null; then
        printf '%s[bt]%s 已连接: %s\n' "$_FZF_HLP_GREEN" "$_FZF_HLP_NC" "$addr"
      else
        printf '%s[bt]%s 连接失败（设备未开机/不在范围）: %s\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC" "$addr"
      fi
      ;;
  esac
}

# ----------------------------------------------------------------------
# bluetooth — 列出已配对蓝牙设备并交互连接或断开。
#
# 设计意图：平台与 blueutil 守护位于函数体内，函数始终定义；列表、解析和动作
# 分派均交给 fzf_list_action。
#
# 参数：无。
# 返回码：0 — 正常结束，包括平台不符、工具缺失或用户取消。
# ----------------------------------------------------------------------
bluetooth() {
  if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s[bt]%s 仅支持 macOS（blueutil）。\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi
  if ! command -v blueutil >/dev/null 2>&1; then
    printf '%s[bt]%s 未检测到 blueutil，请安装: brew install blueutil\n' "$_FZF_HLP_RED" "$_FZF_HLP_NC"
    return 0
  fi
  fzf_list_action '_bt_build_display' 'bt' \
    '[Enter]:连接 | [Ctrl-x]:断开' \
    'cut -f2' _bluetooth_dispatch
}
