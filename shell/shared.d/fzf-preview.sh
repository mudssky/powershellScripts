#!/bin/bash
# ========================================================================
# 文件: fzf-preview.sh
# 作用: 基于 fzf 的文件查找/预览/打开组合命令。
#       - fzf-open(别名 fo): fd 查找文件 → fzf 列出(bat 预览) → 打开/编辑
#       - fzf-search(别名 fs): rg 搜索内容 → fzf 列出(高亮命中) → 打开
#       依赖 fzf-helpers.sh 的 fzf_pick_action 底座(用其 $3 extra_opts 传 preview)。
#
# 命名约定:
#   主函数用完整描述性名(fzf-open / fzf-search), 与 tmux-sessions/
#   zellij-sessions 命名风格一致; 另提供短别名 fo/fs 供高频场景。
#
# 设计原则:
#   - 工具守护放函数体内, 缺失时友好提示而非 command not found。
#   - 预览命令在 fzf 内部以子进程执行, 不能引用本 shell 的函数,
#     必须用独立可执行命令(bat/cat/head 逐级降级)。
#
# 兼容性: bash 与 zsh 双 shell。
# ========================================================================

# ----------------------------------------------------------------------
# _fp_preview_cmd — 返回适合 fzf --preview 的预览命令字符串
#
# 设计意图:
#   fzf 的 --preview 在独立子进程执行, 无法调用当前 shell 函数,
#   故需拼装「纯外部命令」字符串。优先 bat 高亮, 逐级降级到 cat/head。
#   {} 是 fzf 的占位符, 代表当前选中项(文件路径)。
#
# 入参: 无。
# 返回值: 通过 stdout 输出预览命令字符串(含 {} 占位符)。
# ----------------------------------------------------------------------
_fp_preview_cmd() {
  if command -v bat >/dev/null 2>&1; then
    # bat -pp: 纯文本无装饰(pp 双重 plain 同时禁用分页), --color=always 强制彩色,
    # --line-range :100 限制预览长度避免大文件卡顿。
    printf 'bat -pp --color=always --line-range :100 %s 2>/dev/null || cat %s' '{}' '{}'
  elif command -v cat >/dev/null 2>&1; then
    printf 'cat %s 2>/dev/null' '{}'
  else
    printf 'head -100 %s 2>/dev/null' '{}'
  fi
}

# ----------------------------------------------------------------------
# _fp_open — 用系统默认程序打开文件(macOS open / Linux xdg-open)
#
# 入参: $1 文件路径。返回值: 透传打开命令退出码。
# ----------------------------------------------------------------------
_fp_open() {
  if [ "$(uname -s)" = "Darwin" ]; then
    open "$1"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$1"
  else
    printf '%s[fzf-open]%s 无系统打开命令 (需 open/xdg-open)。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 1
  fi
}

# ----------------------------------------------------------------------
# fzf-open — 在当前目录(或指定目录)递归查找文件并交互打开
#
# 设计意图:
#   fd 递归列出文件 → fzf_pick_action(带 preview extra_opts) 选择 → 选中后:
#     Enter   → 用 $EDITOR 打开(默认 vi)
#     Ctrl-x  → 用系统默认程序打开
#   回流 fzf_pick_action 后, 不再内联 fzf 调用, 消灭样板 #3/#4。
#
# 入参: $1(可选) 查找根目录, 默认当前目录。
# 返回码: 0 正常结束(含取消/无文件, 均为友好退出)。
# ----------------------------------------------------------------------
fzf-open() {
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s[fzf-open]%s 请先安装 fzf。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  local search_dir="${1:-.}"
  local files preview_cmd extra_opts

  # 拼装 preview extra_opts 串, 供 fzf_pick_action 的 $3 透传给 fzf。
  # 用单引号包住 preview 命令, 让 fzf_pick_action 按词分割后整体传给 --preview。
  preview_cmd=$(_fp_preview_cmd)
  extra_opts="--preview '$preview_cmd' --preview-window right:50%:wrap"

  # 收集文件列表。优先 fd(快、默认彩色、忽略 gitignore), 降级到 find(POSIX)。
  if command -v fd >/dev/null 2>&1; then
    files=$(fd -t f . "$search_dir" 2>/dev/null)
  elif command -v find >/dev/null 2>&1; then
    files=$(find "$search_dir" -type f -not -path '*/.git/*' 2>/dev/null)
  else
    printf '%s[fzf-open]%s 需要 fd 或 find。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  if [ -z "$files" ]; then
    printf '%s[fzf-open]%s 未找到文件。\n' "${_FZF_HLP_YELLOW:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  # 回流底座: preview 经 $3 透传, 内部统一处理选择+取消+解析。
  # 不能用管道调用函数：bash 会在子 shell 执行管道右侧，导致全局回传变量丢失。
  fzf_pick_action '[Enter]:编辑 | [Ctrl-x]:系统打开' 'ctrl-x' "$extra_opts" <<EOF
$files
EOF
  if [ $? -ne 0 ]; then
    return 0
  fi

  case "$FZF_PICK_ACTION" in
    ctrl-x) _fp_open "$FZF_PICK_ITEM" ;;
    *) "${EDITOR:-vi}" "$FZF_PICK_ITEM" ;;
  esac
}

# ----------------------------------------------------------------------
# fzf-search — 在当前目录按内容搜索(rg)并交互打开命中文件
#
# 设计意图:
#   rg 输出「文件:行号:命中内容」 → fzf_pick_action(带 preview 展示命中文件) →
#   选中后用 $EDITOR 打开到对应行。
#   回流 fzf_pick_action 后, 选择/取消逻辑不再手写。
#
# 入参:
#   $1      - 搜索关键词(正则)。
#   $2(可选) - 搜索根目录, 默认当前目录。
# 返回码: 0 正常结束。
# ----------------------------------------------------------------------
fzf-search() {
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s[fzf-search]%s 请先安装 fzf。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi
  if ! command -v rg >/dev/null 2>&1; then
    printf '%s[fzf-search]%s 请先安装 ripgrep (rg)。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  local query="${1:-}"
  local search_dir="${2:-.}"

  if [ -z "$query" ]; then
    printf '%s[fzf-search]%s 用法: fzf-search <关键词> [目录]\n' "${_FZF_HLP_YELLOW:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  # rg 输出「文件:行号:内容」。--no-heading 保持单行格式, --color=always 供 fzf 着色。
  local matches
  matches=$(rg --line-number --no-heading --color=always "$query" "$search_dir" 2>/dev/null)
  if [ -z "$matches" ]; then
    printf '%s[fzf-search]%s 无匹配结果。\n' "${_FZF_HLP_YELLOW:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  # preview: 用 bat 展示选中行所在文件。fzf 的 --delimiter=: 让 {1} = 文件名。
  # 仅当 bat 可用时启用 preview; 否则不传 preview 参数。
  local extra_opts=""
  if command -v bat >/dev/null 2>&1; then
    extra_opts="--delimiter=: --preview 'bat -pp --color=always {1} 2>/dev/null' --preview-window right:50%:wrap"
  fi

  # 不能用管道调用函数：bash 会在子 shell 执行管道右侧，导致全局回传变量丢失。
  fzf_pick_action '[Enter]:打开到命中行' '' "$extra_opts" <<EOF
$matches
EOF
  if [ $? -ne 0 ]; then
    return 0
  fi

  # 解析「文件:行号:...」: 取第1字段=文件, 第2字段=行号。
  local file lineno rest
  file=${FZF_PICK_ITEM%%:*}
  rest=${FZF_PICK_ITEM#*:}
  lineno=${rest%%:*}

  [ -z "$file" ] && return 0

  # 编辑器跳转到指定行: vim/nvim/code/vscode 支持 +<行号>。
  if [ -n "$lineno" ]; then
    "${EDITOR:-vi}" "+$lineno" "$file"
  else
    "${EDITOR:-vi}" "$file"
  fi
}

# ----------------------------------------------------------------------
# 短别名(高频场景快捷调用)
# 仅当主函数已定义时才设 alias。
# ----------------------------------------------------------------------
if command -v fzf-open >/dev/null 2>&1; then
  alias fo='fzf-open'
fi
if command -v fzf-search >/dev/null 2>&1; then
  alias fs='fzf-search'
fi
