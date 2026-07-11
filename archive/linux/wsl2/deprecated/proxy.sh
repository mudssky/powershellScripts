#! /bin/bash
# 已退役：这是 WSL2 NAT 时代通过 /etc/resolv.conf 猜测 Windows 主机 IP 的代理脚本。
# 现役代理管理器请使用 shell/shared.d/proxy.sh，支持 proxy on/off/docker/container。

# 从 /etc/resolv.conf 中获取主机 IP。
export hostip=$(grep -oP '(?<=nameserver\ ).*' /etc/resolv.conf)
export https_proxy="http://${hostip}:7890"
export http_proxy="http://${hostip}:7890"

# 可以创建 sh 文件执行：
# sudo vim /etc/profile.d/proxy.sh
# source /etc/profile.d/proxy.sh

# 也可以直接写入 ~/.bashrc。
