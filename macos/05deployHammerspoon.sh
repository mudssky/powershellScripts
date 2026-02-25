#!/bin/zsh

# 05deployHammerspoon.sh
# 部署 Hammerspoon 配置到 ~/.hammerspoon/

# 获取脚本所在目录
script_dir=$(cd "$(dirname "$0")" || exit; pwd)
load_script="$script_dir/hammerspoon/load_scripts.zsh"

if [ -f "$load_script" ]; then
    echo 'Deploying Hammerspoon configuration...'
    chmod +x "$load_script"
    zsh "$load_script"
else
    echo "Error: load_scripts.zsh not found at $load_script"
    exit 1
fi
