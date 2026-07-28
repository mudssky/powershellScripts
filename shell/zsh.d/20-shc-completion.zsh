# shc / selfhosted-compose zsh 补全
# 首次冷启动：shc 生成并写入缓存；之后只 source 缓存（不启 node）
[[ -o interactive ]] || return 0
command -v shc >/dev/null 2>&1 || return 0

_shc_bin="$(command -v shc)"
_shc_cache="${XDG_CACHE_HOME:-$HOME/.cache}/selfhosted-compose/completion.zsh"
if [[ ! -s $_shc_cache || $_shc_bin -nt $_shc_cache ]]; then
  mkdir -p "${_shc_cache:h}" 2>/dev/null || true
  # stderr 丢掉 ExperimentalWarning；stdout 由 shc 同时写缓存
  "$_shc_bin" completion zsh >/dev/null 2>/dev/null || true
fi
[[ -s $_shc_cache ]] && source "$_shc_cache"
unset _shc_bin _shc_cache
