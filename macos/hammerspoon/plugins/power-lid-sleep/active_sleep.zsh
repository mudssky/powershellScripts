#!/bin/zsh

# 主动睡眠前置动作执行器。
# 功能：清理防睡眠进程、关闭蓝牙、展示汇总结果，并在成功后进入睡眠。
# 入参：无；由 Hammerspoon 快捷键触发。
# 返回值：以进程退出码表示脚本自身是否正常完成。

set -u

LOG_FILE="$HOME/.hammerspoon/logs/power-lid-sleep.log"
MODE="sleep"
RESULT_FILE="$HOME/.hammerspoon/logs/power-lid-sleep.result"
RESTORE_MARKER_FILE="$HOME/.hammerspoon/logs/power-lid-sleep.restore-bluetooth"
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [ "${1:-}" = "--check-bluetooth-permission" ]; then
    MODE="check-bluetooth-permission"
    RESULT_FILE="${2:-$RESULT_FILE}"
elif [ "${1:-}" = "--restore-bluetooth" ]; then
    MODE="restore-bluetooth"
    RESTORE_MARKER_FILE="${2:-$RESTORE_MARKER_FILE}"
else
    RESULT_FILE="${1:-$RESULT_FILE}"
fi

# 写入诊断日志。
# 入参：$1 日志内容。
# 返回值：无。
log_info() {
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '%s [info] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

# 写入给 Hammerspoon 展示的执行结果。
# 入参：$1 执行状态；$2 执行结果正文。
# 返回值：无。
write_result() {
    local result_status="$1"
    local message="$2"
    mkdir -p "$(dirname "$RESULT_FILE")"
    {
        printf 'status=%s\n' "$result_status"
        printf '%s\n' "$message"
    } > "$RESULT_FILE"
}

# 使用 AppleScript 展示通知。
# 入参：$1 标题；$2 内容。
# 返回值：无。
notify() {
    local title="$1"
    local message="$2"
    /usr/bin/osascript - "$title" "$message" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
    display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

# 清理 caffeinate 防睡眠进程。
# 入参：无。
# 返回值：0 表示成功或未运行，非 0 表示失败。
cleanup_caffeinate() {
    /usr/bin/pkill -TERM -x caffeinate >/dev/null 2>&1
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        log_info "caffeinate 清理完成"
        echo "caffeinate：已清理"
        return 0
    fi

    if [ "$rc" -eq 1 ]; then
        log_info "caffeinate 未运行"
        echo "caffeinate：未运行"
        return 0
    fi

    log_info "caffeinate 清理失败: rc=$rc"
    echo "caffeinate：清理失败 rc=$rc"
    return "$rc"
}

# 检查 Hammerspoon 启动的 blueutil 是否具备蓝牙访问权限。
# 入参：无。
# 返回值：0 表示可访问或无需授权，非 0 表示权限或命令失败。
check_bluetooth_permission() {
    local blueutil_path
    blueutil_path="$(command -v blueutil 2>/dev/null || true)"
    if [ -z "$blueutil_path" ]; then
        log_info "未检测到 blueutil，跳过蓝牙权限预检"
        echo "蓝牙权限：未检测到 blueutil"
        return 0
    fi

    "$blueutil_path" --power >/tmp/power-lid-sleep-blueutil.out 2>/tmp/power-lid-sleep-blueutil.err
    local rc=$?
    local stdout stderr
    stdout="$(tr '\n' ' ' </tmp/power-lid-sleep-blueutil.out 2>/dev/null || true)"
    stderr="$(tr '\n' ' ' </tmp/power-lid-sleep-blueutil.err 2>/dev/null || true)"
    rm -f /tmp/power-lid-sleep-blueutil.out /tmp/power-lid-sleep-blueutil.err

    if [ "$rc" -eq 0 ]; then
        log_info "蓝牙权限预检通过: power=$stdout"
        echo "蓝牙权限：已可访问"
        return 0
    fi

    log_info "蓝牙权限预检失败: rc=$rc stdout=$stdout stderr=$stderr"
    if [[ "$stderr" == *"access to Bluetooth API"* ]]; then
        echo "蓝牙权限：需要允许 Hammerspoon 访问蓝牙"
    else
        echo "蓝牙权限：预检失败 rc=$rc"
    fi
    return "$rc"
}

# 读取蓝牙电源状态。
# 入参：$1 blueutil 可执行文件路径。
# 返回值：成功时输出 0 或 1，并返回 0；失败返回非 0。
read_bluetooth_power() {
    local blueutil_path="$1"
    local power
    power="$("$blueutil_path" --power 2>/tmp/power-lid-sleep-blueutil.err)"
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        local stderr
        stderr="$(tr '\n' ' ' </tmp/power-lid-sleep-blueutil.err 2>/dev/null || true)"
        rm -f /tmp/power-lid-sleep-blueutil.err
        log_info "蓝牙状态读取失败: rc=$rc stderr=$stderr"
        return "$rc"
    fi

    rm -f /tmp/power-lid-sleep-blueutil.err
    power="${power//[[:space:]]/}"
    if [ "$power" = "0" ] || [ "$power" = "1" ]; then
        echo "$power"
        return 0
    fi

    log_info "蓝牙状态读取结果无法解析: power=$power"
    return 1
}

# 标记唤醒后需要恢复蓝牙。
# 入参：$1 关闭前蓝牙状态。
# 返回值：无。
mark_bluetooth_restore() {
    local original_power="$1"
    mkdir -p "$(dirname "$RESTORE_MARKER_FILE")"
    {
        printf 'original_power=%s\n' "$original_power"
        printf 'created_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    } > "$RESTORE_MARKER_FILE"
}

# 恢复蓝牙并清理恢复标记。
# 入参：无。
# 返回值：0 表示已恢复，非 0 表示失败。
restore_bluetooth() {
    local blueutil_path
    blueutil_path="$(command -v blueutil 2>/dev/null || true)"
    if [ -z "$blueutil_path" ]; then
        log_info "蓝牙恢复失败: 未检测到 blueutil"
        return 1
    fi

    "$blueutil_path" --power on >/tmp/power-lid-sleep-blueutil.out 2>/tmp/power-lid-sleep-blueutil.err
    local rc=$?
    local stdout stderr
    stdout="$(tr '\n' ' ' </tmp/power-lid-sleep-blueutil.out 2>/dev/null || true)"
    stderr="$(tr '\n' ' ' </tmp/power-lid-sleep-blueutil.err 2>/dev/null || true)"
    rm -f /tmp/power-lid-sleep-blueutil.out /tmp/power-lid-sleep-blueutil.err

    if [ "$rc" -eq 0 ]; then
        rm -f "$RESTORE_MARKER_FILE"
        log_info "蓝牙恢复完成: stdout=$stdout stderr=$stderr"
        return 0
    fi

    log_info "蓝牙恢复失败: rc=$rc stdout=$stdout stderr=$stderr"
    return "$rc"
}

# 关闭蓝牙。
# 入参：无。
# 返回值：0 表示成功或跳过，非 0 表示失败；蓝牙失败会阻止主动睡眠。
disable_bluetooth() {
    local blueutil_path
    blueutil_path="$(command -v blueutil 2>/dev/null || true)"
    if [ -z "$blueutil_path" ]; then
        log_info "未检测到 blueutil，跳过蓝牙"
        echo "蓝牙：未检测到 blueutil，跳过"
        return 0
    fi

    local original_power
    original_power="$(read_bluetooth_power "$blueutil_path" || true)"

    "$blueutil_path" --power 0 >/tmp/power-lid-sleep-blueutil.out 2>/tmp/power-lid-sleep-blueutil.err
    local rc=$?
    local stdout stderr
    stdout="$(tr '\n' ' ' </tmp/power-lid-sleep-blueutil.out 2>/dev/null || true)"
    stderr="$(tr '\n' ' ' </tmp/power-lid-sleep-blueutil.err 2>/dev/null || true)"
    rm -f /tmp/power-lid-sleep-blueutil.out /tmp/power-lid-sleep-blueutil.err

    if [ "$rc" -eq 0 ]; then
        log_info "蓝牙关闭完成: stdout=$stdout stderr=$stderr"
        if [ "$original_power" = "1" ]; then
            mark_bluetooth_restore "$original_power"
            log_info "已标记唤醒后恢复蓝牙"
        fi
        echo "蓝牙：已关闭"
        return 0
    fi

    log_info "蓝牙关闭失败: rc=$rc stdout=$stdout stderr=$stderr"
    if [[ "$stderr" == *"access to Bluetooth API"* ]]; then
        echo "蓝牙：权限拦截，已取消睡眠"
        echo "需在系统设置给 Hammerspoon 授权蓝牙"
    else
        echo "蓝牙：关闭失败 rc=$rc"
    fi
    return "$rc"
}

if [ "$MODE" = "check-bluetooth-permission" ]; then
    log_info "蓝牙权限预检启动"
    permission_result="$(check_bluetooth_permission)"
    permission_rc=$?
    if [ "$permission_rc" -eq 0 ]; then
        write_result "ok" "$permission_result"
    else
        write_result "failed" "$permission_result"
    fi
    notify "Hammerspoon 蓝牙权限" "$permission_result"
    exit 0
fi

if [ "$MODE" = "restore-bluetooth" ]; then
    log_info "蓝牙恢复执行器启动"
    restore_bluetooth
    exit $?
fi

log_info "主动睡眠执行器启动"

results=()
all_succeeded=true

caffeinate_result="$(cleanup_caffeinate)"
[ "$?" -eq 0 ] || all_succeeded=false
results+=("$caffeinate_result")

bluetooth_result="$(disable_bluetooth)"
[ "$?" -eq 0 ] || all_succeeded=false
results+=("$bluetooth_result")

if [ "$all_succeeded" = true ]; then
    results+=("2 秒后进入睡眠")
else
    results+=("已取消睡眠")
fi

message="$(printf '%s\n' "${results[@]}")"
log_info "主动睡眠执行结果: ${message//$'\n'/ | }"
if [ "$all_succeeded" = true ]; then
    write_result "ok" "$message"
else
    write_result "failed" "$message"
fi
notify "主动睡眠" "$message"

if [ "$all_succeeded" = true ]; then
    sleep 2
    /usr/bin/pmset sleepnow >/dev/null 2>&1
fi

exit 0
