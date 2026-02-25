#!/bin/zsh

# 02installPowerShell.sh
# 通过 Homebrew 安装 PowerShell

command_exists() {
    command -v "$*" >/dev/null 2>&1
}

install_pwsh() {
    if ! command_exists pwsh; then
        echo 'Installing PowerShell...'
        brew install --cask powershell
    else
        echo 'PowerShell is already installed.'
    fi
}

install_pwsh
