#! /bin/bash

# 安装字体
sudo pacman -S noto-fonts-cjk
sudo pacman -S ttf-firacode-nerd
sudo pacman -S ttf-jetbrains-mono-nerd

# 更新字体缓存
fc-cache -fv