# 1. 确保已安装必要的基础软件包（通常已经装了）
sudo pacman -S --needed base-devel git

# 2. 克隆 yay 的源码仓库
git clone https://aur.archlinux.org/yay.git

# 3. 进入目录
cd yay

# 4. 使用 makepkg 编译并安装 yay
makepkg -si