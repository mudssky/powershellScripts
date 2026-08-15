# ======================================================================
# 文件：shc-completion.sh
# 作用：在交互式 Bash 中按需加载 selfhosted-compose 补全缓存。
# 加载方式：首次冷启动由 shc 生成缓存，后续只 source 缓存。
# ======================================================================

# -- interactive guard --------------------------------------------------
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
command -v shc >/dev/null 2>&1 || return 0 2>/dev/null || exit 0

# -- completion cache ---------------------------------------------------
_shc_bin="$(command -v shc)"
_shc_cache="${XDG_CACHE_HOME:-$HOME/.cache}/selfhosted-compose/completion.bash"
if [[ ! -s $_shc_cache || $_shc_bin -nt $_shc_cache ]]; then
  mkdir -p "$(dirname "$_shc_cache")" 2>/dev/null || true
  "$_shc_bin" completion bash >/dev/null 2>/dev/null || true
fi
# shellcheck disable=SC1090
[[ -s $_shc_cache ]] && . "$_shc_cache"
unset _shc_bin _shc_cache
