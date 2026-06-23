#!/bin/zsh

# macOS Finder 右键动作安装脚本。
# 功能：把仓库维护的 Automator workflow 批量安装到当前用户的 Services 目录。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_NAME="$(basename "$0")"

SOURCE_DIR="$SCRIPT_DIR/quick-actions"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_NAME="Fix App Open Issue.workflow"
WORKFLOW_ACTION_ID="fix-app-open-issue"
DRY_RUN=false
UNINSTALL=false

# 显示脚本帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --dry-run     只显示将执行的安装或卸载动作
  --uninstall   从当前用户 Services 目录移除仓库安装的右键动作
  -h, --help    显示帮助
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

# 执行或展示命令说明。
# 入参：$1 操作说明。
# 返回值：dry-run 模式返回 0，否则返回 1 交给调用方执行真实逻辑。
dry_run_action() {
    local message="$1"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY] $message"
        return 0
    fi

    return 1
}

# 生成 workflow 内部 Run Shell Script 的命令内容。
# 入参：无。
# 返回值：向 stdout 输出命令字符串。
build_workflow_command() {
    cat <<EOF
RUNNER_PATH="$REPO_ROOT/macos/quick-actions/run.zsh"
ACTION_ID="$WORKFLOW_ACTION_ID"

if [ ! -f "\$RUNNER_PATH" ]; then
  echo "未找到快捷操作分派器: \$RUNNER_PATH" >&2
  exit 1
fi

/usr/bin/osascript - "\$RUNNER_PATH" "\$ACTION_ID" "\$@" <<'APPLESCRIPT'
on run argv
    if (count of argv) < 2 then return
    set commandText to "/bin/zsh " & quoted form of (item 1 of argv) & " " & quoted form of (item 2 of argv)
    repeat with i from 3 to count of argv
        set commandText to commandText & " " & quoted form of (item i of argv)
    end repeat
    tell application "Terminal"
        activate
        do script commandText
    end tell
end run
APPLESCRIPT
EOF
}

# 校验 workflow 源文件是否完整。
# 入参：$1 workflow 路径。
# 返回值：完整返回 0，否则返回 1。
validate_workflow() {
    local workflow_path="$1"
    local info_plist="$workflow_path/Contents/Info.plist"
    local document_wflow="$workflow_path/Contents/document.wflow"

    if [ ! -f "$info_plist" ]; then
        log_err "缺少 Info.plist: $info_plist"
        return 1
    fi

    if [ ! -f "$document_wflow" ]; then
        log_err "缺少 document.wflow: $document_wflow"
        return 1
    fi

    /usr/bin/plutil -lint "$info_plist" >/dev/null
    /usr/bin/plutil -lint "$document_wflow" >/dev/null
}

# 更新已安装 workflow 的仓库脚本路径。
# 入参：$1 已安装 workflow 路径。
# 返回值：成功返回 0，否则返回 1。
configure_installed_workflow() {
    local workflow_path="$1"
    local document_wflow="$workflow_path/Contents/document.wflow"
    local command_string

    command_string="$(build_workflow_command)"

    if dry_run_action "写入 workflow 命令: $document_wflow"; then
        return 0
    fi

    /usr/bin/plutil -replace actions.0.action.ActionParameters.COMMAND_STRING \
        -string "$command_string" \
        "$document_wflow"
    /usr/bin/plutil -lint "$document_wflow" >/dev/null
}

# 安装仓库维护的 Finder 右键动作。
# 入参：无。
# 返回值：成功返回 0，否则返回 1。
install_quick_actions() {
    local source_workflow="$SOURCE_DIR/$WORKFLOW_NAME"
    local target_workflow="$SERVICES_DIR/$WORKFLOW_NAME"

    validate_workflow "$source_workflow"

    if dry_run_action "创建目录: $SERVICES_DIR"; then
        :
    else
        mkdir -p "$SERVICES_DIR"
    fi

    if dry_run_action "安装 workflow: $source_workflow -> $target_workflow"; then
        :
    else
        rm -rf "$target_workflow"
        /usr/bin/ditto "$source_workflow" "$target_workflow"
    fi

    configure_installed_workflow "$target_workflow"
    if [ "$DRY_RUN" = true ]; then
        log_info "dry-run 完成，未写入 Finder 右键动作"
    else
        log_info "已安装 Finder 右键动作: $target_workflow"
        log_warn "如果 Finder 右键菜单未立即刷新，请重新打开 Finder 窗口或重启 Finder"
    fi
}

# 卸载仓库维护的 Finder 右键动作。
# 入参：无。
# 返回值：成功返回 0，否则返回 1。
uninstall_quick_actions() {
    local target_workflow="$SERVICES_DIR/$WORKFLOW_NAME"

    if [ ! -e "$target_workflow" ]; then
        log_info "右键动作未安装: $target_workflow"
        return 0
    fi

    if dry_run_action "移除 workflow: $target_workflow"; then
        return 0
    fi

    rm -rf "$target_workflow"
    log_info "已移除 Finder 右键动作: $target_workflow"
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
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$UNINSTALL" = true ]; then
    uninstall_quick_actions
else
    install_quick_actions
fi
