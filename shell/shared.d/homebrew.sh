# Homebrew 只从已知安装前缀恢复 PATH，避免执行或持久化外部 source 配置。
_powershell_scripts_brew_prefix=''
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
