# =============================================================================
# Proxy 管理脚本 (Optimized)
# =============================================================================

# --- 1. 配置区域 ---
# 使用 readonly 防止脚本运行时被意外修改
# 增加 _PM_ 前缀 (Proxy Manager) 防止变量名污染
readonly _PM_DEFAULT_HOST="127.0.0.1"
readonly _PM_DEFAULT_PORT="7890"
# 关键优化：默认排除列表，防止开了代理连不上本地服务和内网
readonly _PM_NO_PROXY="localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,100.64.0.0/10"

# --- 2. 核心辅助函数 (不直接暴露给用户) ---
_pm_set_vars() {
    local url="$1"
    
    export http_proxy="$url"
    export https_proxy="$url"
    export ftp_proxy="$url"       # 增加 ftp
    export rsync_proxy="$url"     # 增加 rsync
    export all_proxy="$url"       # 增加 socks/all
    export no_proxy="$_PM_NO_PROXY"

    # 兼容大写 (某些工具只认大写)
    export HTTP_PROXY="$url"
    export HTTPS_PROXY="$url"
    export FTP_PROXY="$url"
    export RSYNC_PROXY="$url"
    export ALL_PROXY="$url"
    export NO_PROXY="$_PM_NO_PROXY"
}

_pm_unset_vars() {
    unset http_proxy https_proxy ftp_proxy rsync_proxy all_proxy no_proxy
    unset HTTP_PROXY HTTPS_PROXY FTP_PROXY RSYNC_PROXY ALL_PROXY NO_PROXY
}

# --- 3. 功能函数 ---

proxy_enable() {
    local host="${1:-$_PM_DEFAULT_HOST}"
    local port="${2:-$_PM_DEFAULT_PORT}"
    local proxy_url="http://${host}:${port}"
    
    # 检测端口 (Bash 特性)
    # 优化：失败时只显示警告但不阻止设置 (有时候你想先设代理再开通道)
    if ! (timeout 0.2 bash -c "</dev/tcp/${host}/${port}") >/dev/null 2>&1; then
        echo "⚠️  警告: 目标端口 ${host}:${port} 似乎未开启，但代理变量已设置。"
    fi
    
    _pm_set_vars "$proxy_url"
    
    echo "✅ Proxy Enabled: $proxy_url"
    echo "   No Proxy:     localhost, 127.0.0.1, internal IPs..."
}

proxy_disable() {
    _pm_unset_vars
    echo "🔴 Proxy Disabled"
}

proxy_status() {
    if [[ -n "$http_proxy" ]]; then
        echo "🟢 Proxy Status: ENABLED"
        echo "   URL:      $http_proxy"
        # 优化：显示 no_proxy，这对排查本地连接问题很有用
        echo "   No Proxy: ${no_proxy:0:50}..." 
        
        # 提取 host 和 port
        # 优化正则：兼容 http:// 和 https:// 前缀移除
        local clean_url="${http_proxy#*://}"
        local host="${clean_url%:*}"
        local port="${clean_url#*:}"
        
        echo -n "   Connectivity: "
        if (timeout 0.2 bash -c "</dev/tcp/${host}/${port}") >/dev/null 2>&1; then
             echo "✅ Online"
        else
             echo "❌ Unreachable (Check your tunnel/app)"
        fi
    else
        echo "🔴 Proxy Status: DISABLED"
    fi
}

proxy_test() {
    local test_url="${1:-https://www.google.com}"
    
    if [[ -z "$http_proxy" ]]; then
        echo "❌ Proxy is OFF. Enable it first."
        return 1
    fi
    
    echo "🔍 Testing: $test_url via $http_proxy"
    
    # 优化：使用 -I (Head) 减少流量，-L 跟随跳转
    if command -v curl >/dev/null 2>&1; then
        # -I: 只请求头
        # -L: 跟随重定向 (比如 http -> https)
        # -w: 格式化输出状态码
        local code
        code=$(curl -I -L -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "$test_url")
        if [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]]; then
            echo "✅ Success (HTTP $code)"
        else
            echo "❌ Failed (HTTP $code)"
        fi
    else
        echo "❌ curl not found."
    fi
}

# --- 4. 自动检测逻辑 ---

proxy_auto_detect() {
    # 只检测默认端口，如果通了就自动开启
    if (timeout 0.2 bash -c "</dev/tcp/${_PM_DEFAULT_HOST}/${_PM_DEFAULT_PORT}") >/dev/null 2>&1; then
        _pm_set_vars "http://${_PM_DEFAULT_HOST}:${_PM_DEFAULT_PORT}"
        # 保持静默，不要 echo，否则影响 scp/sftp 协议
    fi
}

# 运行自动检测
proxy_auto_detect

# --- 5. Aliases ---
alias proxy-on='proxy_enable'
alias proxy-off='proxy_disable'
alias proxy='proxy_status'