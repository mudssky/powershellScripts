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
    # Warning: /home/linuxbrew/.linuxbrew/bin is not in your PATH.
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

# 1. 判断 brew 是否已安装
if ! command -v brew &> /dev/null
then
    echo "Brew not found. Checking network connectivity to official source..."
    
    # 2. 测试官方源连通性 (5秒超时)
    # 使用 -I (HEAD) 减少数据传输，--connect-timeout 设置超时
    if curl --connect-timeout 5 -I https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh &> /dev/null; then
        echo "Network check passed. Using official installer."
        install_brew_official
    else
        echo "Network check failed or timed out. Falling back to Tsinghua mirrors."
        install_brew_cn
    fi
    
    # 3. 配置环境变量
    configure_shell_env
else
    echo "Brew found, skipping installation."
fi

# 安装本地 PowerShell deb 文件的函数
install_local_powershell() {
    echo "Checking for local PowerShell deb files..."
    
    # 查找当前目录下的 PowerShell deb 文件
    local deb_files=($(ls -t powershell_*.deb 2>/dev/null || true))
    
    if [ ${#deb_files[@]} -eq 0 ]; then
        echo "No local PowerShell deb files found."
        return 1
    fi
    
    # 选择最新的 deb 文件
    local latest_deb="${deb_files[0]}"
    echo "Found local PowerShell deb file: $latest_deb"
    
    # 检查 pwsh 是否已安装
    if command -v pwsh &> /dev/null; then
        echo "PowerShell is already installed. Skipping local installation."
        return 0
    fi
    
    echo "Installing PowerShell from local deb file..."
    
    # 安装 deb 包
    if sudo dpkg -i "$latest_deb"; then
        echo "PowerShell package installed successfully."
        
        # 解决可能的依赖问题
        echo "Resolving dependencies..."
        sudo apt-get install -f -y
        
        # 验证安装
        if command -v pwsh &> /dev/null; then
            echo "PowerShell installation completed successfully!"
            echo "PowerShell version: $(pwsh --version)"
            return 0
        else
            echo "Error: PowerShell installation verification failed."
            return 1
        fi
    else
        echo "Error: Failed to install PowerShell deb package."
        return 1
    fi
}

# 4. 安装 PowerShell (重构后的逻辑)
# 首先尝试安装本地 deb 文件，失败则回退到原有脚本
if ! install_local_powershell; then
    echo "Local PowerShell installation failed or not available. Falling back to installer script."
    
    # 注意：确保脚本在 linux/ 目录下执行，否则路径可能不正确
    if [ -f "./ubuntu/installer/install_pwsh.sh" ]; then
        bash ./ubuntu/installer/install_pwsh.sh
    else
        echo "Warning: ./ubuntu/installer/install_pwsh.sh not found. Skipping PowerShell installation."
    fi
fi
