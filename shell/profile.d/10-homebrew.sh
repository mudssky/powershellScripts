# ======================================================================
# 文件：10-homebrew.sh
# 作用：从已知安装位置恢复 Homebrew 环境变量与 PATH。
# 兼容性：Bash / Zsh；macOS 与 Linux。
# ======================================================================

# ----------------------------------------------------------------------
# _setup_homebrew_environment — 查找 Homebrew 并导出基础环境。
# 参数：无。
# 副作用：设置 HOMEBREW_*，并在需要时把 bin/sbin 加入 PATH。
# 返回码：始终返回 0；未安装 Homebrew 时不修改环境。
# ----------------------------------------------------------------------
_setup_homebrew_environment() {
    local prefix=''
    local candidate

    # 显式 prefix 供测试和沙盒使用；正常环境按跨平台默认位置查找。
    if [ -n "${POWERSHELL_SCRIPTS_HOMEBREW_PREFIX:-}" ]; then
        if [ -x "$POWERSHELL_SCRIPTS_HOMEBREW_PREFIX/bin/brew" ]; then
            prefix="$POWERSHELL_SCRIPTS_HOMEBREW_PREFIX"
        fi
    else
        for candidate in \
            /home/linuxbrew/.linuxbrew \
            "$HOME/.linuxbrew" \
            /opt/homebrew \
            /usr/local; do
            if [ -x "$candidate/bin/brew" ]; then
                prefix="$candidate"
                break
            fi
        done
    fi

    [ -n "$prefix" ] || return 0

    export HOMEBREW_PREFIX="$prefix"
    export HOMEBREW_CELLAR="$prefix/Cellar"
    export HOMEBREW_REPOSITORY="$prefix/Homebrew"
    case ":$PATH:" in
        *":$prefix/bin:"*) ;;
        *) export PATH="$prefix/bin:$prefix/sbin:$PATH" ;;
    esac
}

_setup_homebrew_environment
unset -f _setup_homebrew_environment
