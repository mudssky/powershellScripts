#!/bin/bash
# ======================================================================
# 文件：fzf-preview.sh
# 作用：提供文件查找、预览、搜索与交互打开命令。
# 兼容性：Bash / Zsh；依赖 fzf-helpers.sh 的 fzf_pick_action。
# ======================================================================

# ----------------------------------------------------------------------
# _fp_preview_cmd — 返回适合 fzf --preview 的预览命令字符串。
#
# 设计意图：preview 在独立子进程执行，必须使用外部命令并按 bat、cat、head 降级；
# {} 保留为 fzf 文件占位符。
#
# 参数：无。
# 输出：stdout — 含 {} 占位符的预览命令字符串。
# 返回码：printf 的退出码。
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

# _fp_open — 使用系统默认程序打开文件。
# 参数：$1 — 文件路径。
# 返回码：透传 open/xdg-open 退出码；无系统打开命令返回 1。
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
# fzf-open — 在当前目录或指定目录递归查找文件并交互打开。
#
# 设计意图：由 fzf_pick_action 统一处理预览、选择、取消和动作分派；Enter 使用
# EDITOR，Ctrl-x 使用系统默认程序。
#
# 参数：$1 — 可选查找根目录，默认当前目录。
# 返回码：0 — 正常结束，包括取消或无文件。
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
# fzf-search — 按内容搜索并交互打开命中文件。
#
# 设计意图：rg 产出稳定的文件、行号与内容字段，fzf 负责选择，EDITOR 跳转到
# 命中行；取消与解析由底座处理。
#
# 参数：$1 — 搜索关键词（正则）；$2 — 可选搜索根目录，默认当前目录。
# 返回码：0 — 正常结束，包括取消或无匹配。
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

# -- aliases ------------------------------------------------------------
# 仅在主函数已定义时建立短别名。
if command -v fzf-open >/dev/null 2>&1; then
  alias fo='fzf-open'
fi
if command -v fzf-search >/dev/null 2>&1; then
  alias fs='fzf-search'
fi
