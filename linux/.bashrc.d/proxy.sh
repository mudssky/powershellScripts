#!/bin/bash

# =============================================================================
# Proxy Manager (All-in-One)
# =============================================================================

# --- 内部配置 (只读，不暴露) ---
if [ -z "${_PM_DEFAULT_HOST:-}" ]; then
    readonly _PM_DEFAULT_HOST="127.0.0.1"
fi
if [ -z "${_PM_DEFAULT_PORT:-}" ]; then
    readonly _PM_DEFAULT_PORT="7890"
fi
if [ -z "${_PM_NO_PROXY:-}" ]; then
    readonly _PM_NO_PROXY="localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
fi

# --- 主函数: proxy ---
proxy() {
    local cmd="${1:-status}"  # 默认执行 status
    if [[ $# -gt 0 ]]; then
        shift  # 移除第一个参数，方便后面处理参数
    fi

    case "$cmd" in
        on|enable)
            # 用法: proxy on [port] 或 proxy on [host] [port]
            local host="$_PM_DEFAULT_HOST"
            local port="$_PM_DEFAULT_PORT"

            if [[ $# -eq 1 ]]; then
                port="$1" # 如果只传了一个参数，认为是端口
            elif [[ $# -ge 2 ]]; then
                host="$1" # 如果传了两个，第一个是 IP
                port="$2" # 第二个是端口
            fi

            # 设置变量
            local url="http://${host}:${port}"
            export http_proxy="$url" https_proxy="$url" ftp_proxy="$url" rsync_proxy="$url" all_proxy="$url"
            export HTTP_PROXY="$url" HTTPS_PROXY="$url" FTP_PROXY="$url" RSYNC_PROXY="$url" ALL_PROXY="$url"
            export no_proxy="$_PM_NO_PROXY" NO_PROXY="$_PM_NO_PROXY"

            echo "✅ 代理已开启: $url"
            # 尝试静默检测一下连通性，不通则警告
            if ! (timeout 0.1 bash -c "</dev/tcp/${host}/${port}") >/dev/null 2>&1; then
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
                if (timeout 0.1 bash -c "</dev/tcp/${target%:*}"/${target##*:}) >/dev/null 2>&1; then
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
                    local d_host="$_PM_DEFAULT_HOST"
                    local d_port="$_PM_DEFAULT_PORT"
                    
                    if [[ $# -ge 1 ]]; then d_port="$1"; fi
                    if [[ $# -ge 2 ]]; then d_host="$1"; d_port="$2"; fi
                    
                    local d_url="http://${d_host}:${d_port}"
                    
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
                    local d_host="$_PM_DEFAULT_HOST"
                    local d_port="$_PM_DEFAULT_PORT"
                    
                    if [[ $# -ge 1 ]]; then d_port="$1"; fi
                    if [[ $# -ge 2 ]]; then d_host="$1"; d_port="$2"; fi
                    
                    local d_url="http://${d_host}:${d_port}"
                    
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
            echo "  on [port]        开启代理 (默认 7890)"
            echo "  on [host] [port] 开启自定义代理"
            echo "  off              关闭代理"
            echo "  docker [on|off]  配置 Docker Daemon 代理 (需重启, 影响 pull)"
            echo "  container [on]   配置 Docker Container 代理 (无需重启, 影响 run)"
            echo "  status           查看状态 (默认)"
            echo "  test [url]       测试连接"
            ;;

        *)
            echo "❌ 未知命令: $cmd"
            echo "输入 'proxy help' 查看用法"
            return 1
            ;;
    esac
}

# --- 自动补全 (神器) ---
# 输入 proxy 后按 Tab，会自动提示 on, off, status, test
_proxy_completion() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    local commands="on off status test help docker container"
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
}
# 注册补全函数 (仅在 Bash 下有效)
if [ -n "$BASH_VERSION" ]; then
    complete -F _proxy_completion proxy
fi

# --- 自动检测 (静默启动) ---
# 如果默认端口通了，且当前没有设置代理，则自动开启
if [[ -z "$http_proxy" ]] && (timeout 0.1 bash -c "</dev/tcp/${_PM_DEFAULT_HOST}/${_PM_DEFAULT_PORT}") >/dev/null 2>&1; then
    # 直接设置变量，不调用 proxy on 以避免输出文字干扰 scp
    export http_proxy="http://${_PM_DEFAULT_HOST}:${_PM_DEFAULT_PORT}"
    export https_proxy="http://${_PM_DEFAULT_HOST}:${_PM_DEFAULT_PORT}"
    export all_proxy="socks5://${_PM_DEFAULT_HOST}:${_PM_DEFAULT_PORT}"
    export no_proxy="$_PM_NO_PROXY"
    export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy" ALL_PROXY="$all_proxy" NO_PROXY="$no_proxy"
fi