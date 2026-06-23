#!/bin/bash
# ========================================================================
# 文件: bluetooth.sh
# 作用: 基于 fzf 的蓝牙设备交互管理（macOS blueutil）。
#       依赖 fzf-helpers.sh 的 fzf_list_action 薄封装。
#
# 兼容性: 仅 macOS（blueutil 专用）；函数恒定义, 非 macOS 调用时给提示。
#         bash 与 zsh 双 shell。
# ========================================================================

# ----------------------------------------------------------------------
# _bt_parse_device — 解析 blueutil 单行输出为「地址<TAB>名称」
#
# blueutil --paired 输出形如:
#   address: d7-09-7f-38-95-49, not connected, ..., name: "MCHOSE G3 A", ...
# 提取 address 字段(MAC, 作为 --connect/--disconnect 的 ID)与 name 字段(展示)。
#
# 入参: 无(stdin 逐行读 blueutil 原始输出)。
# 返回值: stdout 输出「地址<TAB>名称」每行一个。
# ----------------------------------------------------------------------
_bt_parse_device() {
  sed -nE \
    -e 's/^address: ([^,]+),.*name: "([^"]*)".*/\1\t\2/p' \
    -e 's/^address: ([^,]+),.*$/\1\t(unnamed)/p'
}

# ----------------------------------------------------------------------
# _bt_build_display — 产出 bluetooth 命令的「显示行<TAB>地址」列表
#
# 设计意图:
#   blueutil --is-connected 逐设备查询较慢但设备数少; 在此为每台配对设备
#   拼出「[✓已连]/[ 未连] 名称 (地址)<TAB>地址」的显示行, 喂给 fzf。
#   parser 端用 cut -f2 取 tab 后的地址作为真实值。
#
# 入参: 无。
# 返回值: stdout 输出每行一个「显示行<TAB>地址」。
# ----------------------------------------------------------------------
_bt_build_display() {
  local addr name state
  # 逐行解析 blueutil 配对设备, 补连接状态前缀。
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

# ----------------------------------------------------------------------
# _bluetooth_dispatch — bluetooth 动作分派器
#
# 入参:
#   $1 - 设备地址(MAC, 已解析)。
#   $2 - 动作键: 'ctrl-x' = 断开, 空 = 连接。
# ----------------------------------------------------------------------
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
# bluetooth — 列出已配对蓝牙设备, 交互式连接/断开
#
# 设计意图:
#   声明式: 列表命令用 _bt_build_display(含 blueutil 查询+解析),
#   parser 用 cut -f2 取 tab 后的地址, 分派器 _bluetooth_dispatch。
#   平台/blueutil 守护在此(函数体内), 缺失时友好提示。
#
# 入参: 无。返回码: 0 正常结束。
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
