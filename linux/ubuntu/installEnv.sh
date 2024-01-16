# sudo apt update

source ./functions.sh

git_config() {
	# 不存在则退出脚本执行
	command_must_exists git

	# 配置 git
	git config --global user.name mudssky
	git config --global user.email mudssky@gamil.com
	git config --global core.ignorecase false
}

before_ohmyzsh() {
	install_items=('curl' 'zsh' 'git' 'gh' 'unzip' 'autojump')
	for item in "${install_items[@]}"; do
		install_app_if_not_exists "$item"
	done
	git_config
}

install_ohmyzsh() {
	if [ -e ~/.zshrc ];then
	echo 'ohmyzsh already installed'
	return 0
	fi
	# 安装ohmyzsh
	sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	# ohmyzsh 插件
	# zsh-autosuggestions
	git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
	# zsh-syntax-highlighting
	git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
	# 安装powerline10k 主题
	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k

	if [ -e ~/.zshrc ];then
		mv ~/.zshrc ~/.zshrc.bak-$(date +%s)
	fi

	script_path=$(readlink -f "$BASH_SOURCE")
	# 使用软链接映射zhsrc文件到目标
	ln -s  "$(script_path)/config/.zshrc)"  "$(readpath ~/.zhsrc)"

}

install_brew_app(){
	if ! command_exists brew; then
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		# 加入环境变量
		(echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> ~/.zshrc
		source  ~/.zshrc
	else
		echo 'nvm is already installed'
	fi
	install_items=('starship' )
	for item in "${install_items[@]}"; do
		install_brew_app_if_not_exists "$item"
	done


}


# 使用apt进行安装的内容，次要安装,在关键内容之后
apt_install() {
	install_items=('curl' 'zsh' 'git')
	for item in "${install_items[@]}"; do
		install_app_if_not_exists "$item"
	done
}

install_frontend_env(){
	# 根据nvm的安装目录判断是否存在
	if ! [ -e ~/.nvm ] ; then 
		echo 'Installing nvm ...';
		# 安装nvm
		curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash;
		nvm install --lts;
		nvm use --lts
	fi
	if ! command_exists bun ; then 
		# bun安装
		curl -fsSL https://bun.sh/install | bash
	fi

	install_items=('tldr')
	for item in "${install_items[@]}"; do
		install_npm_app_if_not_exists "$item"
	done
}

install_others(){
	install_brew_app
	apt_install
	install_frontend_env
}



before_ohmyzsh

install_ohmyzsh

install_others


