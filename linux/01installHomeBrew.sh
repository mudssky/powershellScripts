#!/bin/bash

# 01installHomeBrew.sh
# 集成官方源与国内源 (清华源) 的 Homebrew 安装脚本
# 如果官方源连接失败，自动切换到国内源安装

# 定义官方安装函数
install_brew_official() {
    echo "Starting official Homebrew installation..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

# 定义国内源安装函数 (清华源)
install_brew_cn() {
    echo "Starting Homebrew installation using Tsinghua mirrors..."
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
    export HOMEBREW_INSTALL_FROM_API=1

    INSTALL_DIR="~/projects/env" # 指定安装目录

    mkdir -p "${INSTALL_DIR}"

    # 确保清理旧的临时目录
    if [ -d "${INSTALL_DIR}/brew-install" ]; then
        rm -rf "${INSTALL_DIR}/brew-install"
    fi

    git clone --depth=1 https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.git "${INSTALL_DIR}/brew-install"
    /bin/bash "${INSTALL_DIR}/brew-install/install.sh"

    # 清理安装脚本目录
    rm -rf "${INSTALL_DIR}/brew-install"
}

# 配置环境变量函数
configure_shell_env() {
    # 检查环境变量，不存在则进行配置
    if [ -z "$(echo $PATH | grep /home/linuxbrew/.linuxbrew/bin)" ]; then
        echo "Configuring Homebrew environment variables..."

        # 写入 .bashrc (如果尚未存在)
        if ! grep -q "/home/linuxbrew/.linuxbrew/bin/brew shellenv" ~/.bashrc; then
             echo >> ~/.bashrc
             echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
        fi

        # 立即生效
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
}

# 主逻辑开始

# 判断 brew 是否已安装
if ! command -v brew &> /dev/null
then
    echo "Brew not found. Checking network connectivity to official source..."

    # 测试官方源连通性 (5秒超时)
    if curl --connect-timeout 5 -I https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh &> /dev/null; then
        echo "Network check passed. Using official installer."
        install_brew_official
    else
        echo "Network check failed or timed out. Falling back to Tsinghua mirrors."
        install_brew_cn
    fi

    # 配置环境变量
    configure_shell_env
else
    echo "Brew found, skipping installation."
fi
