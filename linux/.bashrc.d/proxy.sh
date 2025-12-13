# =============================================================================
# Proxy 管理脚本
# =============================================================================
# 功能：自动检测和管理 HTTP/HTTPS 代理设置
# 默认端口：7890 (适用于本地代理或 SSH 反向隧道)
# =============================================================================

# 默认代理配置
DEFAULT_PROXY_HOST="127.0.0.1"
DEFAULT_PROXY_PORT="7890"
DEFAULT_PROXY_URL="http://${DEFAULT_PROXY_HOST}:${DEFAULT_PROXY_PORT}"

# =============================================================================
# 自动代理检测 (保持原有逻辑)
# =============================================================================
# 检测端口的方式来自动开启代理
# 一般我们本地在7890端口开启代理，或者使用ssh 反向隧道提供代理时使用这个端口

proxy_auto_detect() {
    # 尝试连接本地 7890 端口 (超时 0.2秒)
    (timeout 0.2 bash -c "</dev/tcp/${DEFAULT_PROXY_HOST}/${DEFAULT_PROXY_PORT}") >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        export http_proxy="$DEFAULT_PROXY_URL"
        export https_proxy="$DEFAULT_PROXY_URL"
        export HTTP_PROXY="$DEFAULT_PROXY_URL"
        export HTTPS_PROXY="$DEFAULT_PROXY_URL"
        # 可选：打印提示 (建议注释掉，否则 scp/sftp 可能会因为输出文字而报错)
        # echo "🟢 SSH Proxy Auto-Enabled"
        return 0
    fi
    return 1
}

# 执行自动检测
proxy_auto_detect

# =============================================================================
# Proxy 管理函数
# =============================================================================

# 启用代理
# 用法: proxy_enable [host] [port]
proxy_enable() {
    local host="${1:-$DEFAULT_PROXY_HOST}"
    local port="${2:-$DEFAULT_PROXY_PORT}"
    local proxy_url="http://${host}:${port}"
    
    # 检查代理端口是否可用
    if ! (timeout 2 bash -c "</dev/tcp/${host}/${port}") >/dev/null 2>&1; then
        echo "❌ 错误: 无法连接到代理服务器 ${host}:${port}"
        return 1
    fi
    
    # 设置代理环境变量
    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"
    export HTTP_PROXY="$proxy_url"
    export HTTPS_PROXY="$proxy_url"
    
    echo "✅ 代理已启用: $proxy_url"
    return 0
}

# 禁用代理
# 用法: proxy_disable
proxy_disable() {
    unset http_proxy
    unset https_proxy
    unset HTTP_PROXY
    unset HTTPS_PROXY
    
    echo "🔴 代理已禁用"
    return 0
}

# 检查代理状态
# 用法: proxy_status
proxy_status() {
    if [[ -n "$http_proxy" ]]; then
        echo "🟢 代理状态: 已启用"
        echo "   HTTP_PROXY: $HTTP_PROXY"
        echo "   HTTPS_PROXY: $HTTPS_PROXY"
        
        # 测试代理连接
        local proxy_host=$(echo "$http_proxy" | sed 's|http://||' | cut -d':' -f1)
        local proxy_port=$(echo "$http_proxy" | sed 's|http://||' | cut -d':' -f2)
        
        if (timeout 2 bash -c "</dev/tcp/${proxy_host}/${proxy_port}") >/dev/null 2>&1; then
            echo "   连接状态: ✅ 正常"
        else
            echo "   连接状态: ❌ 无法连接"
        fi
    else
        echo "🔴 代理状态: 未启用"
    fi
}

# 设置自定义代理配置
# 用法: proxy_set <proxy_url>
# 示例: proxy_set http://proxy.example.com:8080
proxy_set() {
    if [[ $# -eq 0 ]]; then
        echo "❌ 错误: 请提供代理 URL"
        echo "用法: proxy_set <proxy_url>"
        echo "示例: proxy_set http://proxy.example.com:8080"
        return 1
    fi
    
    local proxy_url="$1"
    
    # 验证 URL 格式
    if [[ ! "$proxy_url" =~ ^https?:// ]]; then
        echo "❌ 错误: 代理 URL 必须以 http:// 或 https:// 开头"
        return 1
    fi
    
    # 提取主机和端口进行连接测试
    local host_port=$(echo "$proxy_url" | sed 's|^https?://||')
    local host=$(echo "$host_port" | cut -d':' -f1)
    local port=$(echo "$host_port" | cut -d':' -f2)
    
    if [[ -z "$port" ]]; then
        echo "❌ 错误: 无法从 URL 中提取端口号"
        return 1
    fi
    
    # 测试连接
    if ! (timeout 2 bash -c "</dev/tcp/${host}/${port}") >/dev/null 2>&1; then
        echo "⚠️  警告: 无法连接到代理服务器 ${host}:${port}"
        echo "是否继续设置? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # 设置代理
    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"
    export HTTP_PROXY="$proxy_url"
    export HTTPS_PROXY="$proxy_url"
    
    echo "✅ 代理已设置: $proxy_url"
    return 0
}

# 测试代理连接
# 用法: proxy_test [test_url]
proxy_test() {
    local test_url="${1:-http://www.google.com}"
    
    if [[ -z "$http_proxy" ]]; then
        echo "❌ 错误: 代理未启用"
        return 1
    fi
    
    echo "🔍 测试代理连接..."
    echo "代理服务器: $http_proxy"
    echo "测试目标: $test_url"
    
    # 使用 curl 测试代理连接
    if command -v curl >/dev/null 2>&1; then
        if curl -s --connect-timeout 5 --max-time 10 "$test_url" >/dev/null 2>&1; then
            echo "✅ 代理连接测试成功"
            return 0
        else
            echo "❌ 代理连接测试失败"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --timeout=10 --tries=1 "$test_url" >/dev/null 2>&1; then
            echo "✅ 代理连接测试成功"
            return 0
        else
            echo "❌ 代理连接测试失败"
            return 1
        fi
    else
        echo "❌ 错误: 系统中未找到 curl 或 wget 命令"
        return 1
    fi
}

# 显示帮助信息
# 用法: proxy_help
proxy_help() {
    cat << 'EOF'
📚 Proxy 管理函数使用说明

🔧 基本命令:
  proxy_enable [host] [port]     启用代理 (默认: 127.0.0.1:7890)
  proxy_disable                  禁用代理
  proxy_status                   查看代理状态
  proxy_set <proxy_url>          设置自定义代理
  proxy_test [test_url]          测试代理连接
  proxy_help                     显示此帮助信息

📝 使用示例:
  proxy_enable                   # 启用默认代理 (127.0.0.1:7890)
  proxy_enable 192.168.1.100 8080  # 启用自定义代理
  proxy_set http://proxy.company.com:3128  # 设置公司代理
  proxy_test http://www.google.com        # 测试代理访问 Google
  proxy_status                   # 查看当前代理状态

💡 提示:
  - 自动检测: 脚本会在启动时自动检测 7890 端口并启用代理
  - 环境变量: 设置的代理会同时应用于 http_proxy, https_proxy, HTTP_PROXY, HTTPS_PROXY
  - 连接测试: 启用/设置代理时会自动测试连接可用性

EOF
}

# 创建便捷别名
alias proxy-on='proxy_enable'
alias proxy-off='proxy_disable'
alias proxy='proxy_status'