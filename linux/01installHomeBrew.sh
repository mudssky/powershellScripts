
install_brew() {
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # 检查环境变量，不存在则进行配置
    # Warning: /home/linuxbrew/.linuxbrew/bin is not in your PATH.
    # 检查环境变量，不存在则进行配置
    if [ -z "$(echo $PATH | grep /home/linuxbrew/.linuxbrew/bin)" ]; then
        echo >> ~/.bashrc
        echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
}



# 判断brew是否安装
if ! command -v brew &> /dev/null
then
    echo "brew not found, install it"
    install_brew
else
    echo "brew found, skip install"
fi

bash ./ubuntu/installer/install_pwsh.sh