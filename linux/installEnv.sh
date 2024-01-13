# 常用软件安装
sudo apt install unzip



# 配置 git
git config --global user.name mudssky
git config --global user.email mudssky@gamil.com
git config --global core.ignorecase false  


# 终端配置
# 安装zsh
sudo apt-get install zsh -y
chsh -s /bin/zsh ## 设为默认终端 安装ohmyzsh时会提示你
# 安装ohmyzsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# ohmyzsh 插件
# zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
# zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
# autojump
sudo apt-get install autojump
# 需要修改~/.zhsrc 配置,把插件填进去
# plugins=(
#         autojump
#         extract # 解压缩
#         git
#         rand-quote # 随机展示格言
#         vi-mode
#         zsh-syntax-highlighting
#         zsh-autosuggestions
#         )
# 建议直接把配置文件写一份放到github上.

# 安装nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
# 安装lts版本的node
nvm install --lts
# bun安装
curl -fsSL https://bun.sh/install | bash




# 安装github gh
sudo apt install gh









