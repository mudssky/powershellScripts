#!/bin/bash

# 02installPowerShell.sh
# 安装 PowerShell：优先使用本地 deb 文件，失败则回退到 installer 脚本

# 安装本地 PowerShell deb 文件的函数
install_local_powershell() {
    echo "Checking for local PowerShell deb files..."

    # 获取脚本所在目录
    local script_dir
    script_dir=$(cd "$(dirname "$0")" || exit; pwd)

    # 查找脚本目录下的 PowerShell deb 文件
    local deb_files=($(ls -t "$script_dir"/powershell_*.deb 2>/dev/null || true))

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

# 主逻辑：首先尝试安装本地 deb 文件，失败则回退到 installer 脚本
if command -v pwsh &> /dev/null; then
    echo "PowerShell is already installed: $(pwsh --version)"
    exit 0
fi

if ! install_local_powershell; then
    echo "Local PowerShell installation failed or not available. Falling back to installer script."

    # 获取脚本所在目录
    script_dir=$(cd "$(dirname "$0")" || exit; pwd)

    if [ -f "$script_dir/ubuntu/installer/install_pwsh.sh" ]; then
        bash "$script_dir/ubuntu/installer/install_pwsh.sh"
    else
        echo "Warning: ubuntu/installer/install_pwsh.sh not found. Skipping PowerShell installation."
    fi
fi
