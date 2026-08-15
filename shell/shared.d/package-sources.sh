#!/usr/bin/env sh
# ======================================================================
# 文件：package-sources.sh
# 作用：从受管 package source env 文件加载严格白名单内的 HTTPS 变量。
# 兼容性：POSIX sh；仅导入明确允许的变量。
# ======================================================================
# ----------------------------------------------------------------------
# _load_package_sources_env — 读取并导出受管 package source 环境变量。
#
# 设计意图：只接受白名单变量、双引号值与 HTTPS 地址，避免 source 任意本机内容。
#
# 参数：$1 — 可选 env 文件路径；默认使用 XDG_CONFIG_HOME 或 ~/.config。
# 副作用：导出通过校验的 package source 环境变量。
# 返回码：始终返回 0；非法行被忽略，避免本机文件损坏中断 shell 初始化。
# ----------------------------------------------------------------------
_load_package_sources_env() {
    local config_root package_source_file line assignment name quoted_value value

    config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
    package_source_file="${1:-$config_root/powershellScripts/package-sources.env}"
    [ -r "$package_source_file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|'#'*)
                continue
                ;;
            'export '*)
                assignment="${line#export }"
                ;;
            *)
                continue
                ;;
        esac

        case "$assignment" in
            *=*)
                name="${assignment%%=*}"
                quoted_value="${assignment#*=}"
                ;;
            *)
                continue
                ;;
        esac

        case "$name" in
            ''|[0-9]*|*[!A-Z0-9_]*)
                continue
                ;;
        esac
        case "$name" in
            HOMEBREW_BREW_GIT_REMOTE|HOMEBREW_CORE_GIT_REMOTE|HOMEBREW_API_DOMAIN|HOMEBREW_BOTTLE_DOMAIN|RUSTUP_DIST_SERVER|RUSTUP_UPDATE_ROOT)
                ;;
            *)
                continue
                ;;
        esac
        case "$quoted_value" in
            \"*\")
                value="${quoted_value#\"}"
                value="${value%\"}"
                ;;
            *)
                continue
                ;;
        esac
        case "$value" in
            https://*)
                ;;
            *)
                continue
                ;;
        esac
        case "$value" in
            *[[:space:]]*|*\"*)
                continue
                ;;
        esac

        export "$name=$value"
    done < "$package_source_file"

    return 0
}

_load_package_sources_env
