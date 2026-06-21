#!/bin/zsh

# macOS 合盖休眠守卫安装脚本。
# 功能：部署 LaunchAgent，定期运行合盖休眠守卫清理 caffeinate。

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_GUARD="$SCRIPT_DIR/lid-sleep-guard/guard.zsh"
LABEL="com.mudssky.powershellscripts.lid-sleep-guard"
TARGET_DIR="$HOME/Library/Application Support/PowerShellScripts/LidSleepGuard"
TARGET_GUARD="$TARGET_DIR/lid-sleep-guard.zsh"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$LAUNCH_AGENTS_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/PowerShellScripts"
STDOUT_LOG="$LOG_DIR/lid-sleep-guard.out.log"
STDERR_LOG="$LOG_DIR/lid-sleep-guard.err.log"
INTERVAL_SECONDS=10
DRY_RUN=false
UNINSTALL=false

# 显示脚本帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --dry-run      只显示将执行的部署动作
  --uninstall    卸载合盖休眠守卫 LaunchAgent
  -h, --help     显示帮助
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

# 执行或展示命令。
# 入参：命令及其参数。
# 返回值：命令退出码。
run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[DRY] $*${NC}"
        return 0
    fi

    "$@"
}

# 备份将被覆盖的文件。
# 入参：$1 文件路径。
# 返回值：无。
backup_file() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        return
    fi

    local backup_path="${file_path}.$(date +%Y-%m-%d_%H-%M-%S).bak"
    log_warn "备份现有文件: $backup_path"
    run_cmd cp "$file_path" "$backup_path"
}

# 写入 LaunchAgent plist。
# 入参：无。
# 返回值：无。
write_plist() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[DRY] 写入 LaunchAgent: $PLIST_FILE${NC}"
        return
    fi

    /bin/cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$TARGET_GUARD</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>$INTERVAL_SECONDS</integer>
  <key>StandardOutPath</key>
  <string>$STDOUT_LOG</string>
  <key>StandardErrorPath</key>
  <string>$STDERR_LOG</string>
</dict>
</plist>
EOF
}

# 卸载当前用户 LaunchAgent。
# 入参：无。
# 返回值：无。
unload_launch_agent() {
    if [ ! -f "$PLIST_FILE" ]; then
        return
    fi

    run_cmd launchctl bootout "gui/$(id -u)" "$PLIST_FILE" >/dev/null 2>&1 || true
}

# 安装并启动 LaunchAgent。
# 入参：无。
# 返回值：无。
install_guard() {
    if [ ! -f "$SOURCE_GUARD" ]; then
        log_err "守卫脚本不存在: $SOURCE_GUARD"
        exit 1
    fi

    run_cmd mkdir -p "$TARGET_DIR" "$LAUNCH_AGENTS_DIR" "$LOG_DIR"
    backup_file "$TARGET_GUARD"
    backup_file "$PLIST_FILE"

    log_info "部署守卫脚本: $TARGET_GUARD"
    run_cmd cp "$SOURCE_GUARD" "$TARGET_GUARD"
    run_cmd chmod 755 "$TARGET_GUARD"

    write_plist

    if [ "$DRY_RUN" = false ]; then
        plutil -lint "$PLIST_FILE" >/dev/null
    fi

    unload_launch_agent
    log_info "加载 LaunchAgent: $LABEL"
    run_cmd launchctl bootstrap "gui/$(id -u)" "$PLIST_FILE"
    run_cmd launchctl enable "gui/$(id -u)/$LABEL"
    run_cmd launchctl kickstart -k "gui/$(id -u)/$LABEL"
}

# 卸载 LaunchAgent 和托管文件。
# 入参：无。
# 返回值：无。
uninstall_guard() {
    unload_launch_agent

    if [ -f "$PLIST_FILE" ]; then
        log_warn "删除 LaunchAgent: $PLIST_FILE"
        run_cmd rm "$PLIST_FILE"
    fi

    if [ -f "$TARGET_GUARD" ]; then
        log_warn "删除守卫脚本: $TARGET_GUARD"
        run_cmd rm "$TARGET_GUARD"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
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

if [ "$UNINSTALL" = true ]; then
    uninstall_guard
    log_info "合盖休眠守卫已卸载"
    exit 0
fi

install_guard
log_info "合盖休眠守卫已安装"
