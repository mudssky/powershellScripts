command_exists() {
	command -v "$@" >/dev/null 2>&1
}

install_app_if_not_exists() {
	if ! command_exists "$@"; then
		echo "Installing $@"
		sudo apt-get install "$@" -y
	else
		echo "$@ is already installed"
	fi
}

install_brew_app_if_not_exists() {
	if ! command_exists "$@"; then
		echo "Installing $@"
	    brew install "$@" 
	else
		echo "$@ is already installed"
	fi
}

install_npm_app_if_not_exists() {
	if ! command_exists "$@"; then
		echo "Installing $@"
	    npm  install -g  "$@"  
	else
		echo "$@ is already installed"
	fi
}


# 不存在就会退出脚本
command_must_exists() {
	if ! command_exists "$@"; then
		echo "$@ is not installed"
		exit 1
	fi
}

get_timestamp() {

}