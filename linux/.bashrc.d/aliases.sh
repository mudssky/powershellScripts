### 1. 🛡️ 安全与人性化 (Safety & Human Readable)


# 防止ai agent操作时还要人工确认，所以禁用
# 操作文件时询问确认 (防止 rm -rf * 误删)
# alias rm='rm -i'
# alias cp='cp -i'
# alias mv='mv -i'

# 创建目录时自动把父目录也创建了，并显示过程
alias mkdir='mkdir -pv'

# df 和 du 默认显示人类可读单位 (KB, MB, GB) 而不是字节
alias df='df -h'
alias du='du -h'
alias free='free -h'

# grep 搜索自动高亮关键字
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'


### 2. 📂 目录导航与列表 (Navigation)


# 快速列出文件
alias ll='ls -alF --color=auto'  # 列出所有文件(含隐藏)、详细信息、颜色
alias la='ls -A --color=auto'    # 列出所有(不含 . 和 ..)
alias l='ls -CF --color=auto'    # 简单列表


### 3. 🌐 网络与代理 (Network & Proxy)


# 查看本机公网 IP (需要 curl)
alias myip='curl ifconfig.me'

# 查看当前占用端口的进程 (经常用来查 7890 或者是谁占用了 8080)
alias ports='netstat -tulanp'


### 4. 🛠️ 系统管理与进程 (System & Process)


# 快速查找进程 (ps aux | grep 的缩写)
# 用法: psg nginx
alias psg='ps aux | grep -v grep | grep'

# 实时查看系统资源 (如果安装了 htop 优先用 htop，否则用 top)
if command -v htop &> /dev/null; then
    alias top='htop'
fi


# 重新加载 bash 配置 (修改 bashrc 后立生效)
alias reload='source ~/.bashrc && echo "✅ Config reloaded."'

### 5. 📦 Git 专用 (DevOps 必备)

# 🚀 酷炫的 Git Log (在一行显示提交树，带颜色)
alias gl='git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'


### 6. 🕒 时间与历史 (History)

# 默认的 `history` 只有命令没有时间，排查问题很麻烦。


# 让 history 命令显示时间戳 (格式: 2023-12-13 12:00:00 command)
export HISTTIMEFORMAT="%F %T "

# 增加历史记录条数 (默认 1000 太少)
export HISTSIZE=10000
export HISTFILESIZE=20000



