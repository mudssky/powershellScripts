# 从/etc/resolv.conf 中获取主机ip
export hostip=$(cat /etc/resolv.conf |grep -oP '(?<=nameserver\ ).*')
export https_proxy="http://${hostip}:7890";
export http_proxy="http://${hostip}:7890";




# 可以创建sh文件执行
#  sudo vim  /etc/profile.d/proxy.sh
#  source /etc/profile.d/proxy.sh

# 也可以直接写入 ~/.bashrc