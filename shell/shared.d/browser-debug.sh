#!/bin/bash
# ======================================================================
# 文件：browser-debug.sh
# 作用：在 WSL 内通过 Windows pwsh 调用 browser-debug CLI，管理 Windows
#       端 Chromium 调试 Profile（创建快捷方式、启动、停止、CDP 查询）。
# 兼容性：Bash / Zsh；仅 WSL interop 环境注册，其他平台安静降级。
# 加载方式：探测与校验位于 source 时；会话标记阻止重复注册。
# 副作用：注册 browser-debug 函数并保留 _browser_debug_* 状态变量。
# ======================================================================

# 非 Windows 路径布局（无 /mnt/c）说明不是 WSL，直接返回。
if [ ! -d /mnt/c/Windows/System32 ]; then
  return 0
fi

# 交互式会话才注册；AI agent 的非交互调用走 repo-ops reference 的直调命令。
case $- in
*i*) ;;
*) return 0 ;;
esac

# 标记不导出：子 shell 需重新 source 以获得函数定义。
[ -n "${__BROWSER_DEBUG_WRAPPER_READY:-}" ] && return 0

# ----------------------------------------------------------------------
# _browser_debug_resolve_repo_root — 从片段路径还原仓库根目录。
#
# 设计意图：
#   deploy.sh 以软链接方式部署本文件，readlink -f 可还原仓库内真实路径，
#   仓库迁移无需改动本片段。
#
# 参数：$1 — source 时按 Shell 方式取得的片段路径（软链接路径）。
# 输出：stdout — 仓库根目录绝对路径，无法还原时为空。
# 返回码：始终 0。
# ----------------------------------------------------------------------
_browser_debug_resolve_repo_root() {
  local real_path repo_root
  real_path=$(readlink -f "$1" 2>/dev/null) || real_path=""
  # 片段位于 <repo>/shell/shared.d/，向上三级即仓库根。
  repo_root=$(dirname "$(dirname "$(dirname "$real_path")")")
  if [ -f "$repo_root/bin/browser-debug.ps1" ]; then
    printf '%s\n' "$repo_root"
  fi
  return 0
}

if [ -n "${BASH_VERSION:-}" ]; then
  _browser_debug_repo_root=$(_browser_debug_resolve_repo_root "${BASH_SOURCE[0]}")
else
  _browser_debug_repo_root=$(_browser_debug_resolve_repo_root "${(%):-%x}")
fi
# 优先级：软链接还原 > BROWSER_DEBUG_REPO_ROOT 覆盖 > 个人目录默认值。
if [ -z "$_browser_debug_repo_root" ] && [ -n "${BROWSER_DEBUG_REPO_ROOT:-}" ]; then
  _browser_debug_repo_root="$BROWSER_DEBUG_REPO_ROOT"
fi
if [ -z "$_browser_debug_repo_root" ]; then
  _browser_debug_repo_root="$HOME/projects/env/powershellScripts"
fi

# -- Windows pwsh 探测 ----------------------------------------------------
# 不回退 Windows PowerShell 5.1：registry 写入依赖 pwsh 6+ 的
# utf8NoBOM 编码与 File.Move 三参重载。
_browser_debug_pwsh=""
if command -v pwsh.exe >/dev/null 2>&1; then
  _browser_debug_pwsh=$(command -v pwsh.exe)
else
  for _browser_debug_candidate in \
    "/mnt/c/Program Files/PowerShell/7/pwsh.exe" \
    "/mnt/c/Program Files/PowerShell/6/pwsh.exe"; do
    if [ -x "$_browser_debug_candidate" ]; then
      _browser_debug_pwsh="$_browser_debug_candidate"
      break
    fi
  done
  unset _browser_debug_candidate
fi

# 入口 UNC 路径就绪才注册；registry 默认位于 Windows 侧 D 盘，不受本路径影响。
_browser_debug_entry=""
if [ -n "$_browser_debug_pwsh" ] && [ -f "$_browser_debug_repo_root/bin/browser-debug.ps1" ]; then
  _browser_debug_entry=$(wslpath -w "$_browser_debug_repo_root/bin/browser-debug.ps1" 2>/dev/null)
fi

# ----------------------------------------------------------------------
# _browser_debug_ps_quote — 按 PowerShell 单引号字符串规则转义。
#
# 参数：$1 — 待转义值。
# 输出：stdout — 可安全拼入 -Command 的引号包裹字面量。
# 返回码：始终 0。
# ----------------------------------------------------------------------
_browser_debug_ps_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

if [ -n "$_browser_debug_entry" ]; then
  # ----------------------------------------------------------------------
  # browser-debug — 在 WSL 内直调 Windows 端 browser-debug CLI。
  #
  # 设计意图：
  #   - -ExecutionPolicy Bypass 固定携带：RemoteSigned 将 UNC 路径视为
  #     不可信区域，缺少该参数时入口脚本必被拦截。
  #   - 用 -Command 前置 [Console]::OutputEncoding=UTF8：Windows pwsh
  #     对重定向 stdout 默认输出系统 ANSI 代码页，中文会变乱码。
  #   - 参数在 shell 侧完成 PowerShell 转义后拼入命令串，不依赖 pwsh
  #     对 -Command 尾部参数的空格分割，含空格路径可完整透传。
  #
  # 参数：透传 browser-debug 全部命令树，见 `browser-debug help`。
  # 返回码：透传 Windows pwsh 进程退出码。
  # ----------------------------------------------------------------------
  browser-debug() {
    local -a translated
    local arg converted invocation quoted
    for arg in "$@"; do
      # `/` 开头且真实存在的参数视为 WSL 路径，转 Windows 路径后透传。
      case "$arg" in
      /*)
        if [ -e "$arg" ]; then
          converted=$(wslpath -w "$arg" 2>/dev/null) && arg="$converted"
        fi
        ;;
      esac
      translated+=("$arg")
    done
    invocation="$_browser_debug_entry_invocation"
    for arg in "${translated[@]}"; do
      quoted=$(_browser_debug_ps_quote "$arg")
      invocation="$invocation $quoted"
    done
    "$_browser_debug_pwsh" -NoProfile -ExecutionPolicy Bypass \
      -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; & $invocation"
  }
  _browser_debug_entry_invocation=$(_browser_debug_ps_quote "$_browser_debug_entry")
  __BROWSER_DEBUG_WRAPPER_READY=1
fi
