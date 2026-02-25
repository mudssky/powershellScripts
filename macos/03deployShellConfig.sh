#!/bin/zsh

# 03deployShellConfig.sh
# 部署 shell 配置：调用 shell/deploy.sh + symlink .zshrc

# 获取脚本所在目录
script_dir=$(cd "$(dirname "$0")" || exit; pwd)

# 1. 部署 shell 配置片段
deploy_script="$script_dir/../shell/deploy.sh"

if [ -f "$deploy_script" ]; then
    echo 'Deploying shell configuration snippets...'
    chmod +x "$deploy_script"
    bash "$deploy_script" --shell zsh
else
    echo "Warning: deploy.sh not found at $deploy_script"
fi

# 2. Symlink .zshrc
config_zshrc() {
    if [ -e ~/.zshrc ]; then
        cp ~/.zshrc ~/.zshrc.bak-"$(date +%s)"
        rm ~/.zshrc
    fi

    echo "script_path: $script_dir"
    # 使用软链接映射 .zshrc 文件到目标
    ln -s "$script_dir/config/.zshrc" ~/.zshrc
    echo 'Symlinked .zshrc successfully.'
}

config_zshrc
