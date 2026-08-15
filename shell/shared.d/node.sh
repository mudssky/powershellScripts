# ======================================================================
# 文件：node.sh
# 作用：初始化 Node.js 工具链与 package.json 脚本选择命令。
# 兼容性：Bash / Zsh。
# ======================================================================

# -- fnm ----------------------------------------------------------------
if command -v fnm &> /dev/null; then
  eval "$(fnm env --use-on-cd)"
fi

# -- bun completions ----------------------------------------------------
# Bun 生成的是 zsh completion；共享片段在 Bash 下也会 source，因此只在 Zsh 加载。
if [ -n "${ZSH_VERSION:-}" ] && [ -s "$HOME/.bun/_bun" ]; then
  source "$HOME/.bun/_bun"
fi

# -- bun ----------------------------------------------------------------
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# -- pnpm ---------------------------------------------------------------
# 保留显式配置；仅为支持的系统补齐 pnpm 用户目录。
if [ -z "${PNPM_HOME+x}" ]; then
  case "$(uname -s)" in
    Darwin) PNPM_HOME="$HOME/Library/pnpm" ;;
    Linux) PNPM_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm" ;;
  esac
fi

# 只在全局 bin 目录存在且 PATH 尚未包含时追加，保证重复加载幂等。
if [ -n "${PNPM_HOME:-}" ] && [ -d "$PNPM_HOME/bin" ]; then
  export PNPM_HOME
  case ":$PATH:" in
    *":$PNPM_HOME/bin:"*) ;;
    *) export PATH="$PNPM_HOME/bin:$PATH" ;;
  esac
fi

# ----------------------------------------------------------------------
# _pkg_find_root — 从当前目录向上查找最近的 package.json 所在目录。
#
# 设计意图：
#   以 package.json 所在目录作为执行目录，避免从子目录运行时相对路径漂移。
#
# 参数：无。
# 输出：
#   stdout — package.json 所在目录的绝对路径。
# 返回码：
#   0 — 找到 package.json。
#   1 — 到达文件系统根目录仍未找到。
# ----------------------------------------------------------------------
_pkg_find_root() {
  local dir="$PWD"

  while [ "$dir" != "/" ]; do
    if [ -f "$dir/package.json" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  if [ -f "/package.json" ]; then
    printf '%s\n' "/"
    return 0
  fi

  return 1
}

# ----------------------------------------------------------------------
# _pkg_detect_runner — 根据 package.json 与 lockfile 推断脚本运行器。
#
# 设计意图：
#   优先使用 packageManager，缺失时按 lockfile 判断，最后回退 npm。
#
# 参数：$1 — package 根目录。
# 输出：
#   stdout — npm、pnpm、yarn 或 bun。
# 返回码：0 — 始终完成推断。
# ----------------------------------------------------------------------
_pkg_detect_runner() {
  local package_root="$1"
  local package_manager runner

  package_manager=$(jq -r '.packageManager // empty' "$package_root/package.json" 2>/dev/null)
  runner=${package_manager%%@*}

  case "$runner" in
    pnpm | yarn | bun | npm)
      printf '%s\n' "$runner"
      return 0
      ;;
  esac

  if [ -f "$package_root/pnpm-lock.yaml" ]; then
    printf '%s\n' pnpm
  elif [ -f "$package_root/yarn.lock" ]; then
    printf '%s\n' yarn
  elif [ -f "$package_root/bun.lock" ] || [ -f "$package_root/bun.lockb" ]; then
    printf '%s\n' bun
  else
    printf '%s\n' npm
  fi
}

# _pkg_run_script — 使用指定运行器执行 package.json script。
# 参数：$1 — 运行器名称（npm、pnpm、yarn 或 bun）；$2 — script 名称。
# 返回码：透传包管理器退出码；未知运行器返回 1。
_pkg_run_script() {
  local runner="$1"
  local script_name="$2"

  case "$runner" in
    pnpm | npm | bun)
      "$runner" run "$script_name"
      ;;
    yarn)
      yarn run "$script_name"
      ;;
    *)
      printf '%s[pkg-scripts]%s 未知脚本运行器: %s\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}" "$runner"
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------
# package-scripts — 用 jq 与 fzf 选择并执行当前项目 package.json scripts。
#
# 设计意图：
#   使用机器可读脚本数据并在 package 根目录执行，避免展示文案或子目录 cwd
#   影响真实命令。
#
# 参数：无。
# 返回码：
#   0 — 正常结束，包括缺依赖、无脚本或用户取消。
#   非 0 — 选中脚本执行失败时透传运行器退出码。
# ----------------------------------------------------------------------
package-scripts() {
  if ! command -v jq >/dev/null 2>&1; then
    printf '%s[pkg-scripts]%s 请先安装 jq。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s[pkg-scripts]%s 请先安装 fzf。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  local package_root package_json scripts runner preview_cmd extra_opts script_name old_pwd run_status

  package_root=$(_pkg_find_root)
  if [ -z "$package_root" ]; then
    printf '%s[pkg-scripts]%s 当前目录向上未找到 package.json。\n' "${_FZF_HLP_YELLOW:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  package_json="$package_root/package.json"
  scripts=$(jq -r '.scripts // {} | to_entries[] | [.key, .value] | @tsv' "$package_json" 2>/dev/null)
  if [ -z "$scripts" ]; then
    printf '%s[pkg-scripts]%s package.json 中没有 scripts。\n' "${_FZF_HLP_YELLOW:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  runner=$(_pkg_detect_runner "$package_root")
  if ! command -v "$runner" >/dev/null 2>&1; then
    printf '%s[pkg-scripts]%s 未检测到 %s，请先安装。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}" "$runner"
    return 0
  fi

  # {1} / {2..} 由 fzf 按选中行字段替换，用于预览最终运行命令与脚本内容。
  preview_cmd="printf \"%s\\n\\n%s\\n\" \"$runner run {1}\" \"{2..}\""
  extra_opts="--delimiter '\t' --with-nth=1,2.. --preview '$preview_cmd' --preview-window down:4:wrap"

  fzf_pick_action "[Enter]:执行脚本 | runner: $runner | root: $package_root" "" "$extra_opts" <<EOF
$scripts
EOF
  if [ $? -ne 0 ]; then
    return 0
  fi

  script_name=$(printf '%s\n' "$FZF_PICK_ITEM" | cut -f1)
  if [ -z "$script_name" ]; then
    printf '%s[pkg-scripts]%s 无法解析选中脚本。\n' "${_FZF_HLP_RED:-}" "${_FZF_HLP_NC:-}"
    return 0
  fi

  old_pwd="$PWD"
  cd "$package_root" || return 1
  _pkg_run_script "$runner" "$script_name"
  run_status=$?
  cd "$old_pwd" || return "$run_status"
  return "$run_status"
}

# -- aliases ------------------------------------------------------------
# 高频场景快捷调用，仅在主函数已定义时建立别名。
if command -v package-scripts >/dev/null 2>&1; then
  alias pscripts='package-scripts'
fi
