#!/bin/bash
# ========================================================================
# 文件: fzf-preview.sh
# 作用: 基于 fzf 的文件查找/预览/打开组合命令。
#       - fo(fzf-open): fd 查找文件 → fzf 列出(bat 预览) → 打开/编辑
#       - fs(fzf-search): rg 搜索内容 → fzf 列出(高亮命中) → 打开
#       依赖 fzf-helpers.sh 的 fzf_pick_action 底座与 modern-tools.sh 的 bat。
#
# 设计原则:
#   - 所有工具守护放在函数体内，缺失时友好提示而非 command not found。
#   - 预览命令在 fzf 内部以子进程执行，不能引用本 shell 的函数，
#     必须用独立可执行命令（bat/cat/head 逐级降级）。
#
# 兼容性: bash 与 zsh 双 shell。
# ========================================================================

# ----------------------------------------------------------------------
# _fp_preview_cmd — 返回适合 fzf --preview 的预览命令字符串
#
# 设计意图:
#   fzf 的 --preview 在独立子进程执行，无法调用当前 shell 函数，
#   故需拼装一个「纯外部命令」字符串。优先用 bat 高亮，逐级降级到 cat/head。
#   {} 是 fzf 的占位符，代表当前选中项（文件路径）。
#
# 入参: 无。
# 返回值: 通过 stdout 输出预览命令字符串（含 {} 占位符）。
# ----------------------------------------------------------------------
_fp_preview_cmd() {
  if command -v bat >/dev/null 2>&1; then
    # bat -pp: 纯文本无装饰（pp 双重 plain 同时禁用分页），--color=always 强制彩色，
    # --line-range :100 限制预览长度避免大文件卡顿。
    printf 'bat -pp --color=always --line-range :100 %s 2>/dev/null || cat %s' '{}' '{}'
  elif command -v cat >/dev/null 2>&1; then
    printf 'cat %s 2>/dev/null' '{}'
  else
    printf 'head -100 %s 2>/dev/null' '{}'
  fi
}

# ----------------------------------------------------------------------
# fo — fzf-open: 在当前目录(或指定目录)递归查找文件并交互打开
#
# 设计意图:
#   fd 递归列出文件 → fzf 以 bat 预览展示 → 选中后:
#     Enter   → 用 $EDITOR 打开（默认 vi）
#     Ctrl-x  → 用系统默认程序打开（macOS open / Linux xdg-open）
#
# 入参:
#   $1(可选) - 查找根目录，默认当前目录。
#
# 返回码: 0 正常结束（含取消/无文件，均为友好退出）。
#
# 健壮性: fd/fzf/bat 缺失逐级降级；find 兜底；空结果友好提示。
# ----------------------------------------------------------------------
fo() {
  # 工具守护：fzf 必需，fd/find 至少一个。
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s[fo]%s 请先安装 fzf。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  local search_dir="${1:-.}"
  local files preview_cmd

  preview_cmd=$(_fp_preview_cmd)

  # 收集文件列表。优先 fd（快、默认彩色、忽略 gitignore），
  # 降级到 find（POSIX 兼容）。两者都输出「相对/绝对路径」每行一个。
  if command -v fd >/dev/null 2>&1; then
    # -t f: 仅普通文件; -H: 含隐藏(但排除 .git 由 fd 默认 ignore 处理)。
    files=$(fd -t f . "$search_dir" 2>/dev/null)
  elif command -v find >/dev/null 2>&1; then
    # find 降级: -type f 仅文件, 排除 .git 目录避免噪音。
    files=$(find "$search_dir" -type f -not -path '*/.git/*' 2>/dev/null)
  else
    printf '%s[fo]%s 需要 fd 或 find。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  if [ -z "$files" ]; then
    printf '%s[fo]%s 未找到文件。\n' "${_FZF_HLP_YELLOW:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  # fzf 交互: --preview 在子进程执行预览命令; preview_cmd 含 {} 占位符。
  # 因需要 --preview/--preview-window 等 fzf_pick_action 未暴露的参数,
  # 此处直接内联 fzf 并自行解析 --expect 输出（与底座同样的两行格式）。
  # Enter=默认(编辑), Ctrl-x=系统打开。
  local selection
  selection=$(printf '%s\n' "$files" | fzf --height=60% --reverse \
    --preview "$preview_cmd" \
    --preview-window=right:50%:wrap \
    --header='[Enter]:编辑 | [Ctrl-x]:系统打开' \
    --expect=ctrl-x)
  local rc=$?
  if [ $rc -ne 0 ] || [ -z "$selection" ]; then
    return 0
  fi

  local key file
  {
    read -r key
    read -r file
  } <<EOF
$selection
EOF

  [ -z "$file" ] && return 0

  case "$key" in
    ctrl-x)
      # 系统默认程序打开: macOS 用 open, Linux 用 xdg-open。
      if [ "$(uname -s)" = "Darwin" ]; then
        open "$file"
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$file"
      else
        printf '%s[fo]%s 无系统打开命令 (需 open/xdg-open)。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
      fi
      ;;
    *)
      # 默认用 $EDITOR 打开; 未设置则退到 vi。
      "${EDITOR:-vi}" "$file"
      ;;
  esac
}

# ----------------------------------------------------------------------
# fs — fzf-search: 在当前目录按内容搜索(rg)并交互打开命中文件
#
# 设计意图:
#   rg 输出「文件:行号:命中内容」 → fzf 展示(预览命中处上下文) →
#   选中后用 $EDITOR 打开到对应行。
#
# 入参:
#   $1      - 搜索关键词（正则）。
#   $2(可选) - 搜索根目录，默认当前目录。
#
# 返回码: 0 正常结束（含无命中/取消，均为友好退出）。
#
# 健壮性: rg 忺需; 无命中友好提示; 编辑器跳转行号格式兼容 vi/vim/nvim/code。
# ----------------------------------------------------------------------
fs() {
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s[fs]%s 请先安装 fzf。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi
  if ! command -v rg >/dev/null 2>&1; then
    printf '%s[fs]%s 请先安装 ripgrep (rg)。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  local query="${1:-}"
  local search_dir="${2:-.}"

  if [ -z "$query" ]; then
    printf '%s[fs]%s 用法: fs <关键词> [目录]\n' "${_FZF_HLP_YELLOW:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  # rg 输出格式: 文件:行号:内容。--no-heading 保持单行格式便于 fzf 展示。
  # --line-number 带行号, --color=always 供 fzf 着色, --hidden 含隐藏但 .git 默认忽略。
  local matches
  matches=$(rg --line-number --no-heading --color=always "$query" "$search_dir" 2>/dev/null)
  if [ -z "$matches" ]; then
    printf '%s[fs]%s 无匹配结果。\n' "${_FZF_HLP_YELLOW:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  # fzf 交互: 预览用 bat 展示选中行所在文件, 高亮关键词便于定位。
  # fzf 的 {} 含完整「文件:行号:内容」, 用 awk 取文件名喂给预览。
  local selection
  selection=$(printf '%s\n' "$matches" | fzf --height=60% --reverse \
    --delimiter=: \
    --preview 'bat -pp --color=always {1} 2>/dev/null' \
    --preview-window=right:50%:wrap \
    --header='[Enter]:打开到命中行')
  local rc=$?
  if [ $rc -ne 0 ] || [ -z "$selection" ]; then
    return 0
  fi

  # 解析「文件:行号:...」: 取第 1 字段=文件, 第 2 字段=行号。
  local file lineno
  file=${selection%%:*}
  local rest=${selection#*:}
  lineno=${rest%%:*}

  [ -z "$file" ] && return 0

  # 编辑器跳转到指定行: vim/nvim/code/vscode 支持 +<行号>。
  # 其他编辑器忽略行号直接打开文件。
  if [ -n "$lineno" ]; then
    "${EDITOR:-vi}" "+$lineno" "$file"
  else
    "${EDITOR:-vi}" "$file"
  fi
}
