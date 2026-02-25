#!/bin/zsh

# 01installHomeBrew.sh
# 安装 Homebrew（仅 Homebrew 安装，不包含 PowerShell 和 shell 配置）

command_exists() {
    command -v "$*" >/dev/null 2>&1
}

install_brew() {
    if ! command_exists brew; then
        echo 'Installing brew...'
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        echo 'Homebrew is already installed.'
    fi
}

install_brew
