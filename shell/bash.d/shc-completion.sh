# shc / selfhosted-compose bash 补全
# 首次冷启动：shc 生成并写入缓存；之后只 source 缓存（不启 node）
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
command -v shc >/dev/null 2>&1 || return 0 2>/dev/null || exit 0

_shc_bin="$(command -v shc)"
_shc_cache="${XDG_CACHE_HOME:-$HOME/.cache}/selfhosted-compose/completion.bash"
if [[ ! -s $_shc_cache || $_shc_bin -nt $_shc_cache ]]; then
  mkdir -p "$(dirname "$_shc_cache")" 2>/dev/null || true
  "$_shc_bin" completion bash >/dev/null 2>/dev/null || true
fi
# shellcheck disable=SC1090
[[ -s $_shc_cache ]] && . "$_shc_cache"
unset _shc_bin _shc_cache
