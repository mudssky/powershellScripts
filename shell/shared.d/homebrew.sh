# ======================================================================
# 文件：homebrew.sh
# 作用：从已知安装前缀恢复 Homebrew 环境变量与 PATH。
# 兼容性：Bash / Zsh；macOS 与 Linux。
# 设计意图：显式测试覆盖优先，避免执行或持久化外部 source 配置。
# ======================================================================

# -- brew prefix --------------------------------------------------------
# 候选顺序与 linux/01installHomeBrew.sh 的 find_linuxbrew 保持一致。
_powershell_scripts_brew_prefix=''

# 显式 prefix 用于测试或沙盒时跳过其它路径探测。
if [ -n "${POWERSHELL_SCRIPTS_HOMEBREW_PREFIX:-}" ]; then
    if [ -x "${POWERSHELL_SCRIPTS_HOMEBREW_PREFIX}/bin/brew" ]; then
        _powershell_scripts_brew_prefix="$POWERSHELL_SCRIPTS_HOMEBREW_PREFIX"
    fi
else
    for _powershell_scripts_brew_candidate in \
        /home/linuxbrew/.linuxbrew \
        "$HOME/.linuxbrew" \
        /opt/homebrew \
        /usr/local; do
        if [ -x "$_powershell_scripts_brew_candidate/bin/brew" ]; then
            _powershell_scripts_brew_prefix="$_powershell_scripts_brew_candidate"
            break
        fi
    done
fi

# -- brew environment ---------------------------------------------------
if [ -n "$_powershell_scripts_brew_prefix" ]; then
    export HOMEBREW_PREFIX="$_powershell_scripts_brew_prefix"
    export HOMEBREW_CELLAR="$_powershell_scripts_brew_prefix/Cellar"
    export HOMEBREW_REPOSITORY="$_powershell_scripts_brew_prefix/Homebrew"
    case ":$PATH:" in
        *":$_powershell_scripts_brew_prefix/bin:"*) ;;
        *) export PATH="$_powershell_scripts_brew_prefix/bin:$_powershell_scripts_brew_prefix/sbin:$PATH" ;;
    esac
fi

unset _powershell_scripts_brew_candidate _powershell_scripts_brew_prefix
