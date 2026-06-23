#!/bin/bash
# ========================================================================
# 文件: bluetooth.sh
# 作用: 基于 fzf 的蓝牙设备交互管理（macOS blueutil）。
#       列出已配对设备，交互式连接/断开。
#       依赖 fzf-helpers.sh 的 fzf_pick_action 底座。
#
# 兼容性: 仅 macOS（blueutil 为 macOS 专用）；非 macOS 时函数加载但不报错。
#         bash 与 zsh 双 shell。
# ========================================================================

# 非 macOS 整体不加载函数体逻辑——但函数仍定义，调用时给出平台提示，
# 而非 command not found（与 tmux.sh/zellij.sh 同样的守护策略）。

# ----------------------------------------------------------------------
# _bt_parse_device — 解析 blueutil 单行输出为「地址<TAB>名称」格式
#
# 设计意图:
#   blueutil --paired 输出形如:
#     address: d7-09-7f-38-95-49, not connected, not favourite, paired, name: "MCHOSE G3 A", ...
#   需提取 address 字段（MAC，作为 --connect/--disconnect 的 ID）与 name 字段（展示）。
#   用 sed 而非复杂正则，保持 bash/zsh 双兼容。
#
# 入参: 无（从 stdin 逐行读取 blueutil 原始输出）。
# 返回值: 通过 stdout 输出「地址<TAB>名称」每行一个。
# ----------------------------------------------------------------------
_bt_parse_device() {
  # 第 1 个 s: 取 'address: ' 后、逗号前的 MAC。
  # 第 2 个 s: 取 'name: "' 后、引号前的设备名（无 name 时为空）。
  # 最终输出「MAC<tab>名称」，tab 作为分隔符便于后续 ${var%%$'\t'*} 切割。
  sed -nE \
    -e 's/^address: ([^,]+),.*name: "([^"]*)".*/\1\t\2/p' \
    -e 's/^address: ([^,]+),.*$/\1\t(unnamed)/p'
}

# ----------------------------------------------------------------------
# bluetooth — 列出已配对蓝牙设备，交互式连接/断开
#
# 设计意图:
#   blueutil 列出已配对设备 → fzf 展示(带连接状态前缀) → 选中后:
#     Enter   → 连接（若已连接则提示）
#     Ctrl-x  → 断开
#   复用 fzf_pick_action 底座，与 tmux-sessions/zellij-sessions 范式一致。
#
# 入参: 无。
#
# 返回码: 0 正常结束（含无设备/工具缺失/用户取消，均为友好退出）。
#
# 健壮性:
#   - 非 macOS / blueutil 缺失 → 提示并返回 0。
#   - 无配对设备 → 提示并返回 0。
#   - 连接/断开失败（设备离线等）→ 提示错误原因。
# ----------------------------------------------------------------------
bluetooth() {
  # 平台与工具守护（运行时检查，函数恒定义）。
  if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s[bt]%s 仅支持 macOS（blueutil）。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi
  if ! command -v blueutil >/dev/null 2>&1; then
    printf '%s[bt]%s 未检测到 blueutil，请安装: brew install blueutil\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s[bt]%s 请先安装 fzf。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi
  if ! command -v fzf_pick_action >/dev/null 2>&1; then
    printf '%s[bt]%s 底座 fzf-helpers.sh 未加载，请检查部署。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  # 读取已配对设备原始输出。
  local raw
  raw=$(blueutil --paired 2>/dev/null)
  if [ -z "$raw" ]; then
    printf '%s[bt]%s 没有已配对的蓝牙设备。\n' "${_FZF_HLP_YELLOW:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  # 构造「显示行」: 每行 = [连接状态] 名称 (地址)。
  # 先解析出「地址<tab>名称」，再查每台设备的连接状态拼前缀。
  # 由于 blueutil --is-connected 逐设备调用较慢但设备数少，可接受。
  local display_lines=""
  local addr name state
  while IFS=$'\t' read -r addr name; do
    [ -z "$addr" ] && continue
    # --is-connected 返回 1(已连)/0(未连)。用退出码判断，避免捕获输出。
    if blueutil --is-connected "$addr" >/dev/null 2>&1; then
      state="[✓已连]"
    else
      state="[ 未连]"
    fi
    # 以制表符分隔「显示文本」与「真实地址」，调用方切尾即可取地址。
    display_lines+="${state} ${name} (${addr})"$'\t'"${addr}"$'\n'
  done <<EOF
$(printf '%s\n' "$raw" | _bt_parse_device)
EOF

  if [ -z "$display_lines" ]; then
    printf '%s[bt]%s 未能解析出任何设备。\n' "${_FZF_HLP_YELLOW:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  # 去掉末尾多余换行后交给 fzf。header 标注按键语义。
  printf '%s' "$display_lines" | fzf_pick_action \
    '[Enter]:连接 | [Ctrl-x]:断开'

  if [ $? -ne 0 ]; then
    # 用户取消。
    return 0
  fi

  # 从选中行提取真实地址：显示行结构为「... (地址)<tab>地址」，
  # 取首个 tab 之后的部分即为地址。
  local target_addr
  target_addr="${FZF_PICK_ITEM#*$'\t'}"

  if [ -z "$target_addr" ]; then
    printf '%s[bt]%s 无法解析设备地址。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  case "$FZF_PICK_ACTION" in
    ctrl-x)
      if blueutil --disconnect "$target_addr" 2>/dev/null; then
        printf '%s[bt]%s 已断开: %s\n' "${_FZF_HLP_GREEN:-}" "${_FZF_HLP_NC:-}" "$target_addr"
      else
        printf '%s[bt]%s 断开失败（设备可能未连接）: %s\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}" "$target_addr"
      fi
      ;;
    *)
      if blueutil --connect "$target_addr" 2>/dev/null; then
        printf '%s[bt]%s 已连接: %s\n' "${_FZF_HLP_GREEN:-}" "${_FZF_HLP_NC:-}" "$target_addr"
      else
        printf '%s[bt]%s 连接失败（设备未开机/不在范围）: %s\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}" "$target_addr"
      fi
      ;;
  esac
}
