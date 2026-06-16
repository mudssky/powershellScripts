#!/bin/zsh

# 03deployShellConfig.sh
# 部署 shell 配置：调用 shell/deploy.sh 同步根目录 shell 配置片段。

# 获取脚本所在目录
script_dir=$(cd "$(dirname "$0")" || exit; pwd)

deploy_script="$script_dir/../shell/deploy.sh"

if [ -f "$deploy_script" ]; then
    echo 'Deploying shell configuration snippets...'
    chmod +x "$deploy_script"
    bash "$deploy_script" --shell zsh
else
    echo "Warning: deploy.sh not found at $deploy_script"
fi
