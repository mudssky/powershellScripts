# homebrew bin path
export PATH="/opt/homebrew/bin:$PATH"
# uv 目录
export PATH="$HOME/.local/bin:$PATH"

# pyenv相关配置
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"

# hammerspoon 相关配置
# win.lua相关配置
# 启用修饰键交换（默认行为）
export HAMMERSPOON_MODIFIER_SWAP=true

# ai相关
# ollama配置
export OLLAMA_MODELS='/Volumes/Data/env/.ollama/models'


# Load modular configuration files from ~/.bashrc.d
if [ -d "$HOME/.bashrc.d" ]; then
    for rc in "$HOME/.bashrc.d/"*.sh; do
        if [ -f "$rc" ]; then
            source "$rc"
        fi
    done
fi
