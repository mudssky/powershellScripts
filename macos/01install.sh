#! /bin/zsh
# 这个脚本安装homebrew，powershell这类基础的环境
# 之后可以执行powershell脚本来安装其他软件

command_exists() {
	command -v "$*" >/dev/null 2>&1
}
config_zshrc(){
    if [ -e ~/.zshrc ]; then
		cp ~/.zshrc ~/.zshrc.bak-"$(date +%s)"
		rm ~/.zshrc
	fi

    script_path=$(
		cd $(dirname $0) || exit
		pwd
	)

	echo "script_path:$script_path"
	# 使用软链接映射zhsrc文件到目标
	ln -s "$script_path/config/.zshrc" ~/.zshrc
}
install_brew(){
    if ! command_exists brew; then
        echo 'Installing brew...'
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # 配置 .zshrc   
        config_zshrc
    fi
}

install_pwsh(){
    if ! command_exists pwsh; then
        echo 'Installing pwsh...'
        brew install --cask powershell
    fi
}

install_uv(){
    if ! command_exists uv; then
        echo 'Installing uv...'
        # On macOS and Linux.
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
}

deploy_shell_snippets(){
    # 获取脚本所在目录
    local script_dir
    script_dir=$(cd "$(dirname "$0")" || exit; pwd)
    local deploy_script="$script_dir/../shell/deploy.sh"

    if [ -f "$deploy_script" ]; then
        echo 'Deploying shell configuration snippets...'
        bash "$deploy_script" --shell zsh
    else
        echo "Warning: deploy.sh not found at $deploy_script"
    fi
}

install(){
    install_brew
    config_zshrc
    install_pwsh
    # install_uv
    deploy_shell_snippets
}



install