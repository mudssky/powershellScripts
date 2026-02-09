# 发送 Windows 桌面通知
# 格式: win_notify "标题" "内容"
function win_notify() {
    # \e]9; 是 OSC 9 的开始
    # \e\\ 是结束符
    # Windows Terminal 会捕获这个序列并弹出系统通知
    printf "\e]9;%s;%s\e\\" "$1" "$2"
}

# Zellij中bell字符
function invoke_bell(){
     echo -e "\a"
}