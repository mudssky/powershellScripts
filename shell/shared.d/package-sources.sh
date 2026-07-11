#!/usr/bin/env sh

# 功能：从受管 package source env 文件加载严格的 HTTPS 环境变量。
# 参数：$1 可选 env 文件路径；默认使用 XDG_CONFIG_HOME 或 ~/.config。
# 返回：始终返回 0；非法行被忽略，避免 shell 初始化因本机文件损坏而中断。
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
