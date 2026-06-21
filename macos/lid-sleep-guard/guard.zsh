#!/bin/zsh

# MacBook 合盖休眠守卫。
# 功能：在电池合盖且系统仍保持唤醒时，清理会阻止休眠的命令行进程。

set -u
set -o pipefail

LOG_DIR="$HOME/Library/Logs/PowerShellScripts"
LOG_FILE="$LOG_DIR/lid-sleep-guard.log"
PROCESS_NAMES=("caffeinate")
ONLY_ON_BATTERY=true
DRY_RUN=false
STATUS_ONLY=false

# 显示脚本帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --dry-run      只显示将执行的清理动作
  --status       输出当前合盖、电源和目标进程状态
  -h, --help     显示帮助
EOF
}

# 输出带时间戳的日志。
# 入参：$1 日志内容。
# 返回值：无。
log_info() {
    local message="$1"
    mkdir -p "$LOG_DIR"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$message" >> "$LOG_FILE"
}

# 读取当前合盖状态。
# 入参：无。
# 返回值：成功时输出 Yes 或 No；读取失败返回 1。
read_clamshell_state() {
    local state
    state="$(/usr/sbin/ioreg -r -k AppleClamshellState -d 1 2>/dev/null \
        | /usr/bin/awk -F'= ' '/AppleClamshellState/ {print $2; exit}' \
        | /usr/bin/tr -d '[:space:]')"

    if [ -z "$state" ]; then
        return 1
    fi

    printf '%s\n' "$state"
}

# 判断当前是否合盖。
# 入参：无。
# 返回值：合盖返回 0，否则返回 1。
is_lid_closed() {
    local state
    state="$(read_clamshell_state)" || return 1
    [ "$state" = "Yes" ]
}

# 判断当前是否电池供电。
# 入参：无。
# 返回值：电池供电返回 0，否则返回 1。
is_on_battery() {
    /usr/bin/pmset -g batt 2>/dev/null | /usr/bin/head -n 1 | /usr/bin/grep -Fq "Battery Power"
}

# 判断目标进程是否存在。
# 入参：$1 进程名。
# 返回值：存在返回 0，否则返回 1。
process_exists() {
    local process_name="$1"
    /usr/bin/pgrep -x "$process_name" >/dev/null 2>&1
}

# 终止目标进程。
# 入参：$1 进程名。
# 返回值：成功终止或进程不存在返回 0，否则返回 1。
terminate_process() {
    local process_name="$1"

    if ! process_exists "$process_name"; then
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "[dry-run] 电池合盖，准备清理防睡眠进程: $process_name"
        return 0
    fi

    if /usr/bin/pkill -x -TERM "$process_name"; then
        log_info "电池合盖，已清理防睡眠进程: $process_name"
        return 0
    fi

    log_info "电池合盖，清理防睡眠进程失败: $process_name"
    return 1
}

# 输出当前状态，便于安装后排查。
# 入参：无。
# 返回值：无。
print_status() {
    local clamshell_state="unknown"
    clamshell_state="$(read_clamshell_state 2>/dev/null || printf 'unknown')"

    printf 'clamshell=%s\n' "$clamshell_state"
    if is_on_battery; then
        printf 'power=battery\n'
    else
        printf 'power=external-or-unknown\n'
    fi

    local process_name
    for process_name in "${PROCESS_NAMES[@]}"; do
        if process_exists "$process_name"; then
            printf 'process.%s=running\n' "$process_name"
        else
            printf 'process.%s=not-running\n' "$process_name"
        fi
    done
}

# 执行一次合盖休眠守卫检查。
# 入参：无。
# 返回值：无。
run_once() {
    if [ "$ONLY_ON_BATTERY" = true ] && ! is_on_battery; then
        return
    fi

    if ! is_lid_closed; then
        return
    fi

    local process_name
    for process_name in "${PROCESS_NAMES[@]}"; do
        terminate_process "$process_name"
    done
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --status)
            STATUS_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '未知参数: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$STATUS_ONLY" = true ]; then
    print_status
    exit 0
fi

run_once
