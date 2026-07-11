#!/bin/zsh

# macOS 登录项配置脚本。
# 功能：添加或移除本仓库管理的 GUI 登录项，并在预览时完全绕开 AppleScript。

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false
REMOVE=false
UNATTENDED=false
NON_INTERACTIVE=false
LOGIN_ITEM_NAMES=("Hammerspoon" "Mos")

# 显示脚本帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --dry-run            只显示将执行的登录项配置，不读取或写入系统设置
  --preset Core|Full   由根编排器透传；本步骤只在 Full 注册
  --unattended         接受根编排器交互模式参数
  --non-interactive    接受根编排器交互模式参数
  --remove, --uninstall
                       移除本脚本管理的登录项
  -h, --help           显示帮助
EOF
}

# 输出信息日志。
# 入参：$1 日志内容。
# 返回值：无。
log_info() { echo -e "${GREEN}[INFO] $1${NC}"; }

# 输出提醒日志。
# 入参：$1 日志内容。
# 返回值：无。
log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }

# 输出错误日志。
# 入参：$1 日志内容。
# 返回值：无。
log_err() { echo -e "${RED}[ERROR] $1${NC}" >&2; }

# 判断命令是否存在。
# 入参：$1 命令名称。
# 返回值：命令存在返回 0，否则返回 1。
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 从固定应用目录解析 App bundle，避免通过 Launch Services 弹出或阻塞解析。
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
    set itemName to item 1 of argv
    set appPath to item 2 of argv
    tell application "System Events"
        make login item at end with properties {name:itemName, path:appPath, hidden:false}
    end tell
end run
APPLESCRIPT
}

# 删除登录项。
# 入参：$1 登录项名称。
# 返回值：成功返回 0，否则返回 1。
delete_login_item() {
    local item_name="$1"

    osascript - "$item_name" <<'APPLESCRIPT' >/dev/null
on run argv
    set itemName to item 1 of argv
    tell application "System Events"
        delete every login item whose name is itemName
    end tell
end run
APPLESCRIPT
}

# 确保指定 App 位于登录项。
# 入参：$1 App 名称，不含 .app。
# 返回值：成功返回 0；缺少应用或系统权限返回 10。
ensure_login_item() {
    local app_name="$1"
    local app_path
    local login_status=0

    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[DRY] 确保登录项存在: $app_name（仅在 /Applications 或 ~/Applications 中解析）${NC}"
        return 0
    fi

    if ! app_path="$(resolve_app_path "$app_name")"; then
        log_err "未找到 $app_name.app，请先完成 08 full-apps"
        return 10
    fi

    login_item_exists "$app_name" || login_status=$?
    if [ "$login_status" -eq 0 ]; then
        log_info "登录项已存在: $app_name"
        return 0
    fi
    if [ "$login_status" -eq 2 ]; then
        log_err "无法读取登录项，请确认 System Events 自动化权限"
        return 10
    fi

    if create_login_item "$app_name" "$app_path"; then
        log_info "已添加登录项: $app_name"
        return 0
    fi

    log_err "添加登录项失败: $app_name；请确认 System Events 自动化权限"
    return 10
}

# 移除指定登录项。
# 入参：$1 登录项名称。
# 返回值：成功返回 0；系统权限不足返回 10。
remove_login_item() {
    local app_name="$1"
    local login_status=0

    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[DRY] 移除登录项: $app_name${NC}"
        return 0
    fi

    login_item_exists "$app_name" || login_status=$?
    if [ "$login_status" -eq 1 ]; then
        log_info "登录项不存在，无需移除: $app_name"
        return 0
    fi
    if [ "$login_status" -eq 2 ]; then
        log_err "无法读取登录项，请确认 System Events 自动化权限"
        return 10
    fi

    if delete_login_item "$app_name"; then
        log_info "已移除登录项: $app_name"
        return 0
    fi

    log_err "移除登录项失败: $app_name；请确认 System Events 自动化权限"
    return 10
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --preset)
            [ $# -ge 2 ] || { log_err '--preset 需要一个值'; exit 2; }
            [ "$2" = "Core" ] || [ "$2" = "Full" ] || { log_err '--preset 只支持 Core 或 Full'; exit 2; }
            shift 2
            ;;
        --unattended)
            UNATTENDED=true
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --remove|--uninstall)
            REMOVE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_err "未知参数: $1"
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$UNATTENDED" = true ] && [ "$NON_INTERACTIVE" = true ]; then
    log_err 'unattended 与 non-interactive 不能同时使用'
    exit 2
fi
if [ "$DRY_RUN" = false ] && ! command_exists osascript; then
    log_err "未找到 osascript，无法配置 macOS 登录项"
    exit 10
fi

echo -e "${BLUE}macOS Login Items Configurator${NC}"
echo -e "${BLUE}================================${NC}"

blocked=false
for item_name in "${LOGIN_ITEM_NAMES[@]}"; do
    item_status=0
    if [ "$REMOVE" = true ]; then
        remove_login_item "$item_name" || item_status=$?
    else
        ensure_login_item "$item_name" || item_status=$?
    fi

    if [ "$item_status" -eq 10 ]; then
        blocked=true
    elif [ "$item_status" -ne 0 ]; then
        exit 1
    fi
done

echo
if [ "$blocked" = true ]; then
    log_warn "登录项配置存在外部前置或权限阻塞"
    exit 10
fi

log_info "登录项配置完成"
