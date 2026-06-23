#!/bin/zsh

# macOS Finder 快捷操作通用分派器。
# 功能：接收 workflow 传入的动作 ID 和 Finder 选中路径，并分派到具体动作脚本。

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# 显示脚本帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <action-id> [path...]

Actions:
  fix-app-open-issue  诊断并修复 macOS .app 打不开问题
EOF
}

# 输出错误日志。
# 入参：$1 日志内容。
# 返回值：无。
log_err() { echo "[ERROR] $1" >&2; }

# 分派 Finder 快捷操作。
# 入参：$1 动作 ID；其余参数为 Finder 选中路径。
# 返回值：透传具体动作脚本的退出码；未知动作返回 2。
dispatch_action() {
    local action_id="$1"
    shift

    case "$action_id" in
        fix-app-open-issue)
            /bin/zsh "$SCRIPT_DIR/fix-app-open-issue.zsh" "$@"
            ;;
        *)
            log_err "未知快捷操作: $action_id"
            usage >&2
            return 2
            ;;
    esac
}

if [ $# -lt 1 ]; then
    log_err "缺少动作 ID"
    usage >&2
    exit 2
fi

dispatch_action "$@"
