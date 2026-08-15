# ======================================================================
# 文件：aliases.sh
# 作用：提供安全、导航、网络、系统、Git 与历史相关的交互别名。
# 兼容性：Bash / Zsh。
# ======================================================================

# -- safety and readable output ----------------------------------------
# 禁用需要人工确认的 rm/cp/mv alias，避免 agent 操作时改变交互合同。
# alias rm='rm -i'
# alias cp='cp -i'
# alias mv='mv -i'

# 创建目录时自动建立父目录并显示过程。
alias mkdir='mkdir -pv'

# df 与 du 默认显示人类可读单位；优先使用现代实现，否则保留系统回退。
if command -v duf &> /dev/null; then
    alias df='duf'
else
    alias df='df -h'
fi

if command -v dust &> /dev/null; then
    alias du='dust'
else
    alias du='du -h'
fi

alias free='free -h'

# grep 保留原有语法，仅开启交互高亮。
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'

# -- navigation ---------------------------------------------------------
if command -v eza &> /dev/null; then
    alias ll='eza --long --header --icons --git --all --time-style=iso'
    alias tree='eza --tree --git --icons --git-ignore'
else
    if [ "$(uname -s)" = "Darwin" ]; then
        alias ll='ls -alFG'       # macOS BSD ls: -G 启用颜色
        alias tree='tree -C'
    else
        alias ll='ls -alF --color=auto'  # GNU ls: --color=auto 启用颜色
        alias tree='tree -C'
    fi
fi

if [ "$(uname -s)" = "Darwin" ]; then
    alias la='ls -AG'           # macOS BSD ls
    alias l='ls -CFG'
else
    alias la='ls -A --color=auto'    # 列出所有(不含 . 和 ..)
    alias l='ls -CF --color=auto'    # 简单列表
fi

# -- network ------------------------------------------------------------
alias myip='curl ifconfig.me'
alias ports='netstat -tulanp'

# -- system and process -------------------------------------------------
alias psg='ps aux | grep -v grep | grep'
if command -v htop &> /dev/null; then
    alias top='htop'
fi

# 重新加载当前 Bash/Zsh 配置，使修改立即生效。
alias reload='source "$HOME/.${SHELL##*/}"rc && echo "✅ Config reloaded."'

# -- git ----------------------------------------------------------------
alias gl='git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'

# -- history ------------------------------------------------------------
# 为 history 增加时间戳，并扩大可保留的历史范围。
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=10000
export HISTFILESIZE=20000
