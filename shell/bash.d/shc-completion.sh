# shc / selfhosted-compose bash 补全
# 仅交互式加载；shc 不存在则跳过
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
command -v shc >/dev/null 2>&1 || return 0 2>/dev/null || exit 0
eval "$(shc completion bash)"
