#!/bin/zsh

# macOS 登录项配置脚本。
# 功能：把需要长期生效的 GUI 工具加入当前用户登录项。

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false

LOGIN_ITEM_NAMES=("Hammerspoon" "Mos")

# 显示脚本帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --dry-run   只显示将执行的登录项配置，不写入系统设置
  -h, --help  显示帮助
EOF
}

# 输出信息日志。
# 入参：$1 日志内容。
# 返回值：无。
log_info() { echo -e "${GREEN}✅ $1${NC}"; }

# 输出提醒日志。
# 入参：$1 日志内容。
# 返回值：无。
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# 输出错误日志。
# 入参：$1 日志内容。
# 返回值：无。
log_err() { echo -e "${RED}❌ $1${NC}" >&2; }

# 判断命令是否存在。
# 入参：$1 命令名称。
# 返回值：命令存在返回 0，否则返回 1。
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 执行或展示命令说明。
# 入参：$1 操作说明。
# 返回值：dry-run 模式返回 0，否则返回 1 交给调用方执行真实逻辑。
dry_run_action() {
    local message="$1"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[DRY] $message${NC}"
        return 0
    fi

    return 1
}

# 解析 App bundle 路径。
# 入参：$1 App 名称，不含 .app。
# 返回值：成功时输出 App bundle 路径并返回 0，否则返回 1。
resolve_app_path() {
    local app_name="$1"
    local fixed_path

    for fixed_path in "/Applications/$app_name.app" "$HOME/Applications/$app_name.app"; do
        if [ -d "$fixed_path" ]; then
            printf '%s\n' "$fixed_path"
            return 0
        fi
    done

    if ! command_exists osascript; then
        return 1
    fi

    local resolved_path
    resolved_path="$(osascript - "$app_name" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set appName to item 1 of argv
    try
        return POSIX path of (path to application appName)
    on error
        return ""
    end try
end run
APPLESCRIPT
)"

    if [ -n "$resolved_path" ] && [ -d "$resolved_path" ]; then
        printf '%s\n' "$resolved_path"
        return 0
    fi

    return 1
}

# 判断登录项是否存在。
# 入参：$1 登录项名称。
# 返回值：存在返回 0，不存在返回 1；读取失败返回 2。
login_item_exists() {
    local item_name="$1"
    local result

    if ! result="$(osascript - "$item_name" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set itemName to item 1 of argv
    tell application "System Events"
        repeat with loginItem in login items
            if name of loginItem is itemName then
                return "true"
            end if
        end repeat
    end tell
    return "false"
end run
APPLESCRIPT
)"; then
        return 2
    fi

    [ "$result" = "true" ]
}

# 创建登录项。
# 入参：$1 登录项名称；$2 App bundle 路径。
# 返回值：成功返回 0，否则返回 1。
create_login_item() {
    local item_name="$1"
    local app_path="$2"

    osascript - "$item_name" "$app_path" <<'APPLESCRIPT' >/dev/null
on run argv
    set appPath to item 2 of argv
    tell application "System Events"
        make login item at end with properties {path:appPath, hidden:false}
    end tell
end run
APPLESCRIPT
}

# 确保指定 App 位于登录项。
# 入参：$1 App 名称，不含 .app。
# 返回值：成功返回 0，否则返回 1。
ensure_login_item() {
    local app_name="$1"
    local app_path
    local login_status=0

    if ! app_path="$(resolve_app_path "$app_name")"; then
        log_err "未找到 $app_name.app，请先安装应用"
        return 1
    fi

    if dry_run_action "确保登录项存在: $app_name -> $app_path"; then
        return 0
    fi

    login_item_exists "$app_name" || login_status=$?
    if [ "$login_status" -eq 0 ]; then
        log_info "登录项已存在: $app_name"
        return 0
    fi

    if [ "$login_status" -eq 2 ]; then
        log_err "无法读取登录项，请确认 System Events 自动化权限"
        return 1
    fi

    if create_login_item "$app_name" "$app_path"; then
        log_info "已添加登录项: $app_name"
        return 0
    fi

    log_err "添加登录项失败: $app_name"
    return 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_err "未知参数: $1"
            usage
            exit 2
            ;;
    esac
done

if ! command_exists osascript; then
    log_err "未找到 osascript，无法配置 macOS 登录项"
    exit 1
fi

echo -e "${BLUE}macOS Login Items Configurator${NC}"
echo -e "${BLUE}================================${NC}"

for item_name in "${LOGIN_ITEM_NAMES[@]}"; do
    ensure_login_item "$item_name"
done

echo
log_info "登录项配置完成"
