#! /bin/bash
# sudo apt update

# shellcheck disable=SC1091
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

	if [ -e ~/.zshrc ]; then
		echo 'ohmyzsh already installed'
		return 0
	fi
	# 安装ohmyzsh
	sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	# ohmyzsh 插件
	# zsh-autosuggestions
	git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}"/plugins/zsh-autosuggestions
	# zsh-syntax-highlighting
	git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}"/plugins/zsh-syntax-highlighting
	# 安装powerline10k 主题
	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k

	if [ -e ~/.zshrc ]; then
		mv ~/.zshrc ~/.zshrc.bak-"$(date +%s)"
	fi
	if [ -e ~/.p10k.zsh ]; then
		mv ~/.p10k.zsh ~/.p10k.zsh.bak-"$(date +%s)"
	fi
	# shellcheck disable=SC2128
	# 获取当前脚本所在目录
	script_path=$(
		cd $(dirname $0) || exit
		pwd
	)

	echo "script_path:$script_path"
	# 使用软链接映射zhsrc文件到目标
	ln -s "$script_path/config/.zshrc" "$(realpath ~/.zshrc)"
	ln -s "$script_path/config/.p10k.zsh" "$(realpath ~/.p10k.zsh)"

}

install_brew_app() {
	if ! command_exists brew; then
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		# 加入环境变量
		# shellcheck disable=SC2016
		echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >>~/.zshrc
		# shellcheck disable=SC1090
		source ~/.zshrc
	else
		echo 'nvm is already installed'
	fi
	install_items=('starship' 'navi' 'sccache')
	for item in "${install_items[@]}"; do
		install_brew_app_if_not_exists "$item"
	done

}

# 使用apt进行安装的内容，次要安装,在关键内容之后
apt_install() {
	install_items=('bat' 'ripgrep' 'fd-find' 'hyperfine')
	for item in "${install_items[@]}"; do
		install_app_if_not_exists "$item"
	done
	if ! command_exists gcc; then
		# pyenv 安装python构建需要的
		sudo apt-get install -y make build-essential libssl-dev zlib1g-dev libbz2-dev \
			libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev \
			xz-utils tk-dev libffi-dev liblzma-dev
	fi
	if ! command_exists fd; then
		# fd 名称配置
		# shellcheck disable=SC2046
		ln -s $(which fdfind) ~/.local/bin/fd
	fi
	if ! command_exists bat; then
		# bat名称配置
		mkdir -p ~/.local/bin
		ln -s /usr/bin/batcat ~/.local/bin/bat
	fi
}
script_install() {
	# 安装autin，更好的shell历史记录
	bash <(curl https://raw.githubusercontent.com/ellie/atuin/main/install.sh)
	atuin import auto
}

install_frontend_env() {
	# 根据nvm的安装目录判断是否存在
	if ! [ -e ~/.nvm ]; then
		echo 'Installing nvm ...'
		# 安装nvm
		curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
		[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvmS
		nvm install --lts
		nvm use --lts
	fi
	if ! command_exists bun; then
		# bun安装
		curl -fsSL https://bun.sh/install | bash
	fi

	install_items=('tldr')
	for item in "${install_items[@]}"; do
		install_npm_app_if_not_exists "$item"
	done
}

install_neovim() {
	if ! command_exists nvim; then
		echo 'installing nvim...'
		curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
		sudo rm -rf /opt/nvim
		sudo tar -C /opt -xzf nvim-linux64.tar.gz
		rm nvim-linux64.tar.gz

		# 安装lunarVim
		bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh)
	else
		echo 'nvim is already installed'
	fi
}
install_python() {
	if ! command_exists python; then
		curl https://pyenv.run | bash
		# 列出版本
		# pyenv install -l
		pyenv install 3.12
		pyenv global 3.12
	fi
}
install_others() {
	install_brew_app
	apt_install
	install_frontend_env
	install_python
	install_neovim
}

before_ohmyzsh

install_ohmyzsh

install_others
