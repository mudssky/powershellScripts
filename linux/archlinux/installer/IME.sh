
# 使用fcitx5 输入法
# 1. 安装 Fcitx5 核心和中文输入法引擎
sudo pacman -S fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-chinese-addons

# 2.配置环境变量

# 写入以下内容到 ~/.pam_environment 文件中，写入后重启系统，或者注销重新登录，环境变量会重新载入
# ~/.pam_environment的生效时机是用户登录后，所有其他环境变量都会继承，所以最适合写到这里
# vim ~/.pam_environment
# GTK_IM_MODULE DEFAULT=fcitx
# QT_IM_MODULE DEFAULT=fcitx
# XMODIFIERS DEFAULT=@im=fcitx
# SDL_IM_MODULE DEFAULT=fcitx
# GLFW_IM_MODULE DEFAULT=ibus