#!/usr/bin/env bash
# ========================================================================
# 文件: shc-completion.sh
# 作用: 为 shc / selfhosted-compose 自动加载 bash/zsh 补全。
#       - 不要求手写 eval "$(shc completion zsh)"（自动识别当前 shell）
#       - 生成结果缓存到 XDG cache，避免每次开 shell 都冷启动 node
#       - shc 不存在时静默跳过
#
# 兼容性: bash 与 zsh；shared.d 双 shell 共用。
# 依赖: 00-compinit（zsh）应先于本文件加载（文件名排序已满足）。
# ========================================================================

# 仅交互式 shell 加载补全，避免 scp/非交互脚本踩 compdef/complete
case $- in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

_shc_completion_bin=""
if command -v shc >/dev/null 2>&1; then
  _shc_completion_bin="$(command -v shc)"
elif command -v selfhosted-compose >/dev/null 2>&1; then
  _shc_completion_bin="$(command -v selfhosted-compose)"
else
  unset _shc_completion_bin
  return 0 2>/dev/null || exit 0
fi

_shc_completion_shell=""
if [ -n "${ZSH_VERSION:-}" ]; then
  _shc_completion_shell="zsh"
elif [ -n "${BASH_VERSION:-}" ]; then
  _shc_completion_shell="bash"
else
  unset _shc_completion_bin _shc_completion_shell
  return 0 2>/dev/null || exit 0
fi

_shc_completion_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/selfhosted-compose"
_shc_completion_cache_file="${_shc_completion_cache_dir}/completion.${_shc_completion_shell}"

# 缓存缺失，或 shc 包装器比缓存新时重生（开发态改 CLI 后下次开 shell 生效）
_shc_completion_need_refresh=0
if [ ! -s "${_shc_completion_cache_file}" ]; then
  _shc_completion_need_refresh=1
elif [ -n "${_shc_completion_bin}" ] && [ "${_shc_completion_bin}" -nt "${_shc_completion_cache_file}" ]; then
  _shc_completion_need_refresh=1
fi

if [ "${_shc_completion_need_refresh}" -eq 1 ]; then
  mkdir -p "${_shc_completion_cache_dir}" 2>/dev/null || true
  # 显式传 shell，避免依赖子进程 $SHELL 与当前 shell 不一致
  if ! "${_shc_completion_bin}" completion "${_shc_completion_shell}" >"${_shc_completion_cache_file}.tmp" 2>/dev/null; then
    rm -f "${_shc_completion_cache_file}.tmp" 2>/dev/null || true
  elif [ -s "${_shc_completion_cache_file}.tmp" ]; then
    mv -f "${_shc_completion_cache_file}.tmp" "${_shc_completion_cache_file}" 2>/dev/null || true
  else
    rm -f "${_shc_completion_cache_file}.tmp" 2>/dev/null || true
  fi
fi

if [ -s "${_shc_completion_cache_file}" ]; then
  # shellcheck disable=SC1090
  . "${_shc_completion_cache_file}"
fi

unset _shc_completion_bin _shc_completion_shell _shc_completion_cache_dir \
  _shc_completion_cache_file _shc_completion_need_refresh
