# ======================================================================
# 文件：20-shc-completion.zsh
# 作用：在交互式 Zsh 中按需加载 selfhosted-compose 补全缓存。
# 加载方式：首次冷启动由 shc 生成缓存，后续只 source 缓存。
# ======================================================================

# -- interactive guard --------------------------------------------------
[[ -o interactive ]] || return 0
command -v shc >/dev/null 2>&1 || return 0

# -- completion cache ---------------------------------------------------
_shc_bin="$(command -v shc)"
_shc_cache="${XDG_CACHE_HOME:-$HOME/.cache}/selfhosted-compose/completion.zsh"
if [[ ! -s $_shc_cache || $_shc_bin -nt $_shc_cache ]]; then
  mkdir -p "${_shc_cache:h}" 2>/dev/null || true
  # 丢弃 ExperimentalWarning，避免污染补全生成过程的错误输出。
  "$_shc_bin" completion zsh >/dev/null 2>/dev/null || true
fi
[[ -s $_shc_cache ]] && source "$_shc_cache"
unset _shc_bin _shc_cache
