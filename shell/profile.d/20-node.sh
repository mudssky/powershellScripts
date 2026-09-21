# ======================================================================
# 文件：20-node.sh
# 作用：为 login 与 interactive shell 初始化 fnm、Bun 与 pnpm。
# 兼容性：Bash / Zsh。
# ======================================================================

# _prepend_node_path — 将目录幂等添加到 PATH 前端。
# 参数：$1 — 目录。
# 返回码：始终返回 0。
_prepend_node_path() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) export PATH="$1:$PATH" ;;
    esac
}

# ----------------------------------------------------------------------
# _setup_fnm_environment — 按 shell 模式初始化 fnm。
# 参数：无。
# 副作用：导入 fnm env；交互 shell 额外启用目录切换 hook。
# 返回码：始终返回 0；fnm 不可用或初始化失败时保持当前环境。
# ----------------------------------------------------------------------
_setup_fnm_environment() {
    local mode fnm_env
    case "$-" in
        *i*) mode='interactive' ;;
        *) mode='login' ;;
    esac

    [ "${POWERSHELL_SCRIPTS_FNM_MODE:-}" != "$mode" ] || return 0
    command -v fnm >/dev/null 2>&1 || return 0

    if [ "$mode" = 'interactive' ]; then
        fnm_env=$(fnm env --use-on-cd 2>/dev/null) || fnm_env=''
    else
        fnm_env=$(fnm env 2>/dev/null) || fnm_env=''
    fi
    if [ -n "$fnm_env" ] && eval "$fnm_env" >/dev/null 2>&1; then
        export POWERSHELL_SCRIPTS_FNM_MODE="$mode"
    fi
}

# -- fnm ----------------------------------------------------------------
_setup_fnm_environment

# -- Bun ----------------------------------------------------------------
export BUN_INSTALL="$HOME/.bun"
_prepend_node_path "$BUN_INSTALL/bin"

# -- pnpm ---------------------------------------------------------------
if [ -z "${PNPM_HOME+x}" ]; then
    case "$(uname -s)" in
        Darwin) PNPM_HOME="$HOME/Library/pnpm" ;;
        Linux) PNPM_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm" ;;
    esac
fi
if [ -n "${PNPM_HOME:-}" ] && [ -d "$PNPM_HOME/bin" ]; then
    export PNPM_HOME
    _prepend_node_path "$PNPM_HOME/bin"
fi

unset -f _prepend_node_path _setup_fnm_environment
