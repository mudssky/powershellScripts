#!/bin/bash
# 这个脚本用户在linux环境或者wsl上快速安装配置

# 更新依赖
sudo apt update
# 安装gh
sudo apt install -y gh

gh auth login

# gh 登陆后可以拉取项目
# 判断gh存在
if ! command -v gh &> /dev/null
then
    echo "gh 不存在"
    exit 1
fi

cd ~/

# 判断目录存在
projects/env
if [ ! -d "projects/env" ]; then
    echo "projects/env 目录不存在,创建"
    mkdir -p projects/env
fi

# 进入目录
cd projects/env
# 判断目录存在
if [ -d "powershellScripts" ]; then
    echo "powershellScripts 目录存在,不拉取"
    exit 0
fi
# 拉取项目
gh repo clone mudssky/powershellScripts
