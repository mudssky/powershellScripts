#!/bin/bash

# =============================================================================
# Proxy Manager (All-in-One)
# 兼容 Bash 和 Zsh
# =============================================================================

# --- 内部配置 (只读，不暴露) ---
# 优先使用通用环境变量 PROXY_DEFAULT_HOST/PORT
_PM_DEFAULT_HOST="${PROXY_DEFAULT_HOST:-${_PM_DEFAULT_HOST:-127.0.0.1}}"
_PM_DEFAULT_PORT="${PROXY_DEFAULT_PORT:-${_PM_DEFAULT_PORT:-7890}}"

if [ -z "${_PM_NO_PROXY:-}" ]; then
    readonly _PM_NO_PROXY="localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
fi

# --- 自动开启配置 ---
# 参数: 无；返回值: 0 表示允许自动探测并开启代理，1 表示跳过自动开启。
_pm_auto_enable_enabled() {
    case "${PROXY_AUTO_ENABLE:-1}" in
        0|false|FALSE|False|off|OFF|Off|no|NO|No|n|N)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# --- 代理地址解析 ---
# 参数: $1 为端口、主机或完整代理 URL，$2 为可选端口；返回值: 成功时输出 host|port|url。
_pm_resolve_endpoint() {
    local target="${1:-}"
    local input_port="${2:-}"
    local host="$_PM_DEFAULT_HOST"
    local port="$_PM_DEFAULT_PORT"
    local url=""
    local without_scheme=""
    local scheme=""

    if [[ -n "$target" && "$target" == *"://"* ]]; then
        scheme="${target%%://*}"
        without_scheme="${target#*://}"
        without_scheme="${without_scheme%%/*}"

        if [[ "$without_scheme" == *:* ]]; then
            host="${without_scheme%:*}"
            port="${without_scheme##*:}"
        else
            host="$without_scheme"
            port="$_PM_DEFAULT_PORT"
        fi

        if [[ -z "$host" || -z "$port" ]]; then
            return 1
        fi

        url="${scheme}://${host}:${port}"
    elif [[ -n "$target" && "$target" =~ ^[0-9]+$ ]]; then
        port="$target"
        url="http://${host}:${port}"
    elif [[ -n "$target" ]]; then
        host="$target"
        if [[ -n "$input_port" ]]; then
            port="$input_port"
        fi
        url="http://${host}:${port}"
    else
        url="http://${host}:${port}"
    fi

    printf '%s|%s|%s\n' "$host" "$port" "$url"
}

# --- 跨 shell 端口连通性检测 ---
# /dev/tcp 是 Bash 专属特性，Zsh 不支持
# 优先使用 nc -z，fallback 到 curl，最后 fallback 到 bash /dev/tcp
_pm_check_port() {
    local host="$1"
    local port="$2"
    if command -v nc >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 0.1 nc -z "$host" "$port" >/dev/null 2>&1
        else
            nc -z -G 1 "$host" "$port" >/dev/null 2>&1 || nc -z -w 1 "$host" "$port" >/dev/null 2>&1
        fi
    elif command -v curl >/dev/null 2>&1; then
        curl --connect-timeout 0.1 -s "http://${host}:${port}" >/dev/null 2>&1
    elif command -v bash >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 0.1 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1
        else
            bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1
        fi
    else
        return 1
    fi
}

# --- 主函数: proxy ---
proxy() {
    local cmd="${1:-status}"  # 默认执行 status
    if [[ $# -gt 0 ]]; then
        shift  # 移除第一个参数，方便后面处理参数
    fi

    case "$cmd" in
        on|enable)
            # 用法: proxy on [port]、proxy on [host] [port] 或 proxy on [url]
            local endpoint
            if ! endpoint="$(_pm_resolve_endpoint "${1:-}" "${2:-}")"; then
                echo "❌ 代理地址格式无效: ${1:-}"
                return 1
            fi
            local host="${endpoint%%|*}"
            local rest="${endpoint#*|}"
            local port="${rest%%|*}"
            local url="${rest#*|}"

            # 设置变量
            export http_proxy="$url" https_proxy="$url" ftp_proxy="$url" rsync_proxy="$url" all_proxy="$url"
            export HTTP_PROXY="$url" HTTPS_PROXY="$url" FTP_PROXY="$url" RSYNC_PROXY="$url" ALL_PROXY="$url"
            export no_proxy="$_PM_NO_PROXY" NO_PROXY="$_PM_NO_PROXY"

            echo "✅ 代理已开启: $url"
            # 尝试静默检测一下连通性，不通则警告
            if ! _pm_check_port "$host" "$port"; then
                echo "⚠️  警告: 无法连接到代理端口 ${host}:${port}，请检查隧道是否建立。"
            fi
            ;;

        off|disable|unset)
            unset http_proxy https_proxy ftp_proxy rsync_proxy all_proxy no_proxy
            unset HTTP_PROXY HTTPS_PROXY FTP_PROXY RSYNC_PROXY ALL_PROXY NO_PROXY
            echo "🔴 代理已关闭 (直连模式)"
            ;;

        status|info|show)
            if [[ -n "$http_proxy" ]]; then
                echo "🟢 当前状态: 已开启"
                echo "   地址: $http_proxy"
                echo "   排除: localhost, 局域网等..."
                # 连通性测试
                local target="${http_proxy#*://}" # 去除协议头
                local check_host="${target%:*}"
                local check_port="${target##*:}"
                if _pm_check_port "$check_host" "$check_port"; then
                    echo "   连接: ✅ 正常"
                else
                    echo "   连接: ❌ 无法连接 (服务未启动?)"
                fi
            else
                echo "⚪ 当前状态: 未开启 (直连)"
            fi
            ;;

        docker)
            local subcmd="${1:-status}"
            if [[ $# -gt 0 ]]; then
                shift
            fi
            
            local docker_conf_dir="/etc/systemd/system/docker.service.d"
            local docker_conf_file="${docker_conf_dir}/http-proxy.conf"
            
            case "$subcmd" in
                on|enable|set)
                    local d_endpoint
                    if ! d_endpoint="$(_pm_resolve_endpoint "${1:-}" "${2:-}")"; then
                        echo "❌ 代理地址格式无效: ${1:-}"
                        return 1
                    fi
                    local d_url="${d_endpoint##*|}"
                    
                    echo "⚙️  正在配置 Docker 代理: $d_url ..."
                    
                    if [ ! -d "$docker_conf_dir" ]; then
                        sudo mkdir -p "$docker_conf_dir"
                    fi
                    
                    local content="[Service]\nEnvironment=\"HTTP_PROXY=$d_url\"\nEnvironment=\"HTTPS_PROXY=$d_url\"\nEnvironment=\"NO_PROXY=$_PM_NO_PROXY\""
                    
                    echo -e "$content" | sudo tee "$docker_conf_file" > /dev/null
                    
                    echo "🔄 正在重启 Docker 服务..."
                    sudo systemctl daemon-reload
                    sudo systemctl restart docker
                    
                    echo "✅ Docker 代理已开启。"
                    sudo systemctl show --property=Environment docker
                    ;;
                    
                off|disable|unset)
                    if [ -f "$docker_conf_file" ]; then
                        echo "🗑️  正在移除 Docker 代理配置..."
                        sudo rm "$docker_conf_file"
                        
                        echo "🔄 正在重启 Docker 服务..."
                        sudo systemctl daemon-reload
                        sudo systemctl restart docker
                        
                        echo "🔴 Docker 代理已关闭。"
                    else
                        echo "Docker 代理未设置。"
                    fi
                    ;;
                    
                *)
                    # Status
                    if [ -f "$docker_conf_file" ]; then
                        echo "🟢 Docker 代理已开启:"
                        sudo cat "$docker_conf_file"
                    else
                        echo "⚪ Docker 代理未开启 (直连)"
                    fi
                    ;;
            esac
            ;;

        container)
            local subcmd="${1:-status}"
            shift
            
            local docker_config_dir="$HOME/.docker"
            local docker_config_file="${docker_config_dir}/config.json"
            
            case "$subcmd" in
                on|enable|set)
                    local d_endpoint
                    if ! d_endpoint="$(_pm_resolve_endpoint "${1:-}" "${2:-}")"; then
                        echo "❌ 代理地址格式无效: ${1:-}"
                        return 1
                    fi
                    local d_url="${d_endpoint##*|}"
                    
                    echo "⚙️  正在配置 Docker 容器代理: $d_url ..."
                    
                    if [ ! -d "$docker_config_dir" ]; then
                        mkdir -p "$docker_config_dir"
                    fi
                    
                    if [ ! -f "$docker_config_file" ]; then
                        echo "{}" > "$docker_config_file"
                    fi

                    # Check for jq
                    if ! command -v jq >/dev/null 2>&1; then
                        echo "❌ 错误: 需要 'jq' 工具来处理 JSON 配置。"
                        echo "请安装 jq: sudo apt install jq"
                        return 1
                    fi

                    local tmp_file=$(mktemp)
                    # Safely update JSON using jq
                    jq --arg url "$d_url" --arg no_proxy "$_PM_NO_PROXY" \
                       '.proxies.default.httpProxy = $url | .proxies.default.httpsProxy = $url | .proxies.default.noProxy = $no_proxy' \
                       "$docker_config_file" > "$tmp_file" && mv "$tmp_file" "$docker_config_file"
                    
                    echo "✅ Docker 容器代理已开启 (无需重启 Docker)。"
                    echo "   注意: 仅对新创建的容器生效。"
                    ;;
                    
                off|disable|unset)
                    if [ -f "$docker_config_file" ]; then
                        if ! command -v jq >/dev/null 2>&1; then
                            echo "❌ 错误: 需要 'jq' 工具来处理 JSON 配置。"
                            return 1
                        fi

                        local tmp_file=$(mktemp)
                        jq 'del(.proxies)' "$docker_config_file" > "$tmp_file" && mv "$tmp_file" "$docker_config_file"
                        echo "🔴 Docker 容器代理已关闭。"
                    else
                        echo "Docker 容器代理未设置。"
                    fi
                    ;;
                    
                *)
                    # Status
                    local is_set=0
                    if [ -f "$docker_config_file" ]; then
                         if command -v jq >/dev/null 2>&1; then
                            if jq -e '.proxies.default' "$docker_config_file" >/dev/null 2>&1; then
                                echo "🟢 Docker 容器代理已开启:"
                                jq '.proxies' "$docker_config_file"
                                is_set=1
                            fi
                        fi
                    fi
                    
                    if [ $is_set -eq 0 ]; then
                        echo "⚪ Docker 容器代理未开启 (直连)"
                    fi
                    ;;
            esac
            ;;

        test)
            local url="${1:-https://www.google.com}"
            if [[ -z "$http_proxy" ]]; then
                echo "❌ 错误: 请先开启代理 (proxy on)"
                return 1
            fi
            echo "🔍正在测试访问: $url"
            if command -v curl >/dev/null 2>&1; then
                curl -I -s --connect-timeout 3 "$url" | head -n 1
            else
                echo "❌ 未找到 curl 命令"
            fi
            ;;

        help|--help|-h)
            echo "用法: proxy [命令]"
            echo "  on [port]        开启代理 (默认: $_PM_DEFAULT_HOST:$_PM_DEFAULT_PORT)"
            echo "  on [host] [port] 开启自定义代理"
            echo "  on [url]         开启完整代理地址，例如 http://192.168.21.90:7890"
            echo "  off              关闭代理"
            echo "  docker [on|off]  配置 Docker Daemon 代理 (需重启, 影响 pull)"
            echo "  container [on]   配置 Docker Container 代理 (无需重启, 影响 run)"
            echo "  status           查看状态 (默认)"
            echo "  test [url]       测试连接"
            echo ""
            echo "配置 (环境变量):"
            echo "  PROXY_DEFAULT_HOST   自定义默认主机 (当前: $_PM_DEFAULT_HOST)"
            echo "  PROXY_DEFAULT_PORT   自定义默认端口 (当前: $_PM_DEFAULT_PORT)"
            echo "  PROXY_AUTO_ENABLE    是否自动探测并开启代理 (默认: 1，可设为 0/false/off/no 关闭)"
            ;;

        *)
            echo "❌ 未知命令: $cmd"
            echo "输入 'proxy help' 查看用法"
            return 1
            ;;
    esac
}

# --- 自动补全 ---
# Bash: 使用 complete 内建命令
# Zsh: 使用 compctl 或 compadd
if [ -n "$BASH_VERSION" ]; then
    _proxy_completion() {
        local cur=${COMP_WORDS[COMP_CWORD]}
        local commands="on off status test help docker container"
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    }
    complete -F _proxy_completion proxy
elif [ -n "$ZSH_VERSION" ]; then
    _proxy_completion() {
        local commands=(on off status test help docker container)
        compadd -a commands
    }
    compdef _proxy_completion proxy
fi

# --- 自动检测 (静默启动) ---
# 如果默认端口通了，且当前没有设置代理，则自动开启；可用 PROXY_AUTO_ENABLE=0 关闭。
if _pm_auto_enable_enabled && [ -z "$http_proxy" ] && _pm_check_port "$_PM_DEFAULT_HOST" "$_PM_DEFAULT_PORT"; then
    # 直接设置变量，不调用 proxy on 以避免输出文字干扰 scp
    export http_proxy="http://${_PM_DEFAULT_HOST}:${_PM_DEFAULT_PORT}"
    export https_proxy="http://${_PM_DEFAULT_HOST}:${_PM_DEFAULT_PORT}"
    export all_proxy="socks5://${_PM_DEFAULT_HOST}:${_PM_DEFAULT_PORT}"
    export no_proxy="$_PM_NO_PROXY"
    export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy" ALL_PROXY="$all_proxy" NO_PROXY="$no_proxy"
fi
