# homebrew bin path
export PATH="/opt/homebrew/bin:$PATH"
# uv 目录
export PATH="$HOME/.local/bin:$PATH"

# pyenv相关配置
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"

command_exists() {
	command -v "$*" >/dev/null 2>&1
}

# fnm
if command_exists fnm; then
    eval "$(fnm env --use-on-cd --shell zsh)"
fi

# hammerspoon 相关配置
# win.lua相关配置
# 启用修饰键交换（默认行为）
export HAMMERSPOON_MODIFIER_SWAP=true

# ai相关
# ollama配置
export OLLAMA_MODELS='/Volumes/Data/env/.ollama/models'

