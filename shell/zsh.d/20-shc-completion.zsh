# shc / selfhosted-compose zsh 补全
# 仅交互式加载；shc 不存在则跳过
[[ -o interactive ]] || return 0
command -v shc >/dev/null 2>&1 || return 0
eval "$(shc completion zsh)"
