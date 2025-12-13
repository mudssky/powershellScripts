# 设置7890代理
# 检测端口的方式来自动开启
# 一般我们本地在7890端口开启代理，或者使用ssh 反向隧道提供代理时使用这个端口

# 尝试连接本地 7890 端口 (超时 0.2秒)
(timeout 0.2 bash -c "</dev/tcp/127.0.0.1/7890") >/dev/null 2>&1
if [ $? -eq 0 ]; then
    export http_proxy=http://127.0.0.1:7890
    export https_proxy=http://127.0.0.1:7890
    # 可选：打印提示 (建议注释掉，否则 scp/sftp 可能会因为输出文字而报错)
    # echo "🟢 SSH Proxy Auto-Enabled"
    
fi