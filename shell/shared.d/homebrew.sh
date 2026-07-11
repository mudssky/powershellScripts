# Homebrew 只从已知安装前缀恢复 PATH，避免执行或持久化外部 source 配置。
# 候选顺序与 linux/01installHomeBrew.sh 的 find_linuxbrew 保持一致：
# 系统级 /home/linuxbrew/.linuxbrew 优先于用户级 $HOME/.linuxbrew。
_powershell_scripts_brew_prefix=''

# 测试/沙盒覆盖：显式指定 prefix 时直接采用，跳过所有路径探测，
# 避免 CI（如 ubuntu-latest 预装的系统级 Linuxbrew）干扰隔离 fixture。
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
