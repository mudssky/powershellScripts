#!/bin/zsh

# macOS 应用打开问题处理脚本。
# 功能：批量诊断 Finder 传入的 .app，并在可信来源前提下清除 quarantine 后尝试打开。

set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false

# 显示脚本帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] <app-path>...

Options:
  --dry-run   只显示将执行的处理动作，不清除 quarantine、不打开应用
  -h, --help  显示帮助
EOF
}

# 输出信息日志。
# 入参：$1 日志内容。
# 返回值：无。
log_info() { echo "[INFO] $1"; }

# 输出提醒日志。
# 入参：$1 日志内容。
# 返回值：无。
log_warn() { echo "[WARN] $1"; }

# 输出错误日志。
# 入参：$1 日志内容。
# 返回值：无。
log_err() { echo "[ERROR] $1" >&2; }

# 判断传入路径是否为 App bundle。
# 入参：$1 待检查路径。
# 返回值：是 .app 目录返回 0，否则返回 1。
is_app_bundle() {
    local app_path="$1"
    [ -d "$app_path" ] && [[ "$app_path" == *.app ]]
}

# 执行诊断命令并保留失败输出。
# 入参：$1 标题；其余参数为命令和参数。
# 返回值：命令成功返回 0，否则返回原命令退出码。
run_diagnostic() {
    local title="$1"
    shift

    echo
    echo "$title:"
    "$@" 2>&1
}

# 输出 quarantine 属性状态。
# 入参：$1 App bundle 路径。
# 返回值：检测到 quarantine 返回 0，否则返回 1。
show_quarantine_status() {
    local app_path="$1"
    local quarantine_value

    echo
    echo "隔离属性检查:"
    if quarantine_value="$(/usr/bin/xattr -p com.apple.quarantine "$app_path" 2>/dev/null)"; then
        echo "$quarantine_value"
        return 0
    fi

    echo "未检测到 com.apple.quarantine"
    return 1
}

# 清除 App bundle 的 quarantine 属性。
# 入参：$1 App bundle 路径。
# 返回值：清除成功或 dry-run 返回 0，否则返回 1。
clear_quarantine() {
    local app_path="$1"

    echo
    echo "移除隔离属性:"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY] /usr/bin/xattr -dr com.apple.quarantine '$app_path'"
        return 0
    fi

    /usr/bin/xattr -dr com.apple.quarantine "$app_path" 2>&1
}

# 尝试打开 App bundle。
# 入参：$1 App bundle 路径。
# 返回值：打开命令成功或 dry-run 返回 0，否则返回 1。
open_app() {
    local app_path="$1"

    echo
    echo "尝试打开:"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY] /usr/bin/open '$app_path'"
        return 0
    fi

    /usr/bin/open "$app_path" 2>&1
}

# 处理单个候选路径。
# 入参：$1 Finder 或命令行传入路径。
# 返回值：成功处理或安全跳过返回 0，清除或打开失败返回 1。
process_candidate() {
    local app_path="$1"
    local item_status=0

    echo
    echo "========================================"
    echo "处理: $app_path"

    if ! is_app_bundle "$app_path"; then
        log_warn "跳过：不是 .app 目录"
        return 0
    fi

    run_diagnostic "Gatekeeper 检查" /usr/sbin/spctl -a -vv "$app_path" || true
    run_diagnostic "签名检查" /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path" || true
    show_quarantine_status "$app_path" || true

    if ! clear_quarantine "$app_path"; then
        log_err "移除隔离属性失败: $app_path"
        item_status=1
    fi

    if ! open_app "$app_path"; then
        log_err "打开失败: $app_path"
        item_status=1
    fi

    return "$item_status"
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
        --)
            shift
            break
            ;;
        -*)
            log_err "未知参数: $1"
            usage >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    log_err "缺少 App 路径"
    usage >&2
    exit 2
fi

overall_status=0
for app_path in "$@"; do
    if ! process_candidate "$app_path"; then
        overall_status=1
    fi
done

echo
if [ "$overall_status" -eq 0 ]; then
    log_info "处理完成"
else
    log_err "处理完成，但存在失败项"
fi

exit "$overall_status"
