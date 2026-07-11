#!/bin/zsh

# macOS Finder 快捷操作安装脚本。
# 功能：校验并原子安装仓库维护的单个 workflow，覆盖前保留时间戳备份。

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
UNATTENDED=false
NON_INTERACTIVE=false
TEMP_ROOT=""

# 显示脚本帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --dry-run     只显示将执行的安装或卸载动作
  --preset Core|Full
                由根编排器透传；本步骤只在 Full 注册
  --unattended  接受根编排器交互模式参数
  --non-interactive
                接受根编排器交互模式参数
  --uninstall   从当前用户 Services 目录移除仓库安装的快捷操作
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

# 清理安装过程中创建的临时目录。
# 入参：无。
# 返回值：无。
cleanup_temp() {
    if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf "$TEMP_ROOT"
    fi
}

trap cleanup_temp EXIT INT TERM

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

# 校验 workflow 文件结构和 plist 语法。
# 入参：$1 workflow 路径。
# 返回值：完整且合法返回 0，否则返回 1。
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

# 把当前仓库路径写入临时 workflow，并重新校验 plist。
# 入参：$1 workflow 路径。
# 返回值：写入和校验成功返回 0，否则返回 1。
configure_workflow() {
    local workflow_path="$1"
    local document_wflow="$workflow_path/Contents/document.wflow"
    local command_string
    command_string="$(build_workflow_command)"

    /usr/bin/plutil -replace actions.0.action.ActionParameters.COMMAND_STRING \
        -string "$command_string" \
        "$document_wflow"
    /usr/bin/plutil -lint "$document_wflow" >/dev/null
}

# 生成不会覆盖既有备份的可读时间戳路径。
# 入参：$1 将被覆盖的 workflow 路径。
# 返回值：向 stdout 输出可用备份路径。
new_backup_path() {
    local target_path="$1"
    local timestamp
    local backup_path
    local suffix=0

    timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
    backup_path="${target_path}.${timestamp}.bak"
    while [ -e "$backup_path" ]; do
        suffix=$((suffix + 1))
        backup_path="${target_path}.${timestamp}.${suffix}.bak"
    done
    printf '%s\n' "$backup_path"
}

# 安装仓库维护的 Finder 快捷操作。
# 入参：无。
# 返回值：成功或内容已一致返回 0，否则返回 1。
install_quick_action() {
    local source_workflow="$SOURCE_DIR/$WORKFLOW_NAME"
    local target_workflow="$SERVICES_DIR/$WORKFLOW_NAME"
    local staged_workflow
    local backup_path=""

    validate_workflow "$source_workflow"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY] 校验 workflow: $source_workflow"
        echo "[DRY] 在临时目录配置并校验 workflow"
        if [ -e "$target_workflow" ]; then
            echo "[DRY] 内容变化时备份: $target_workflow.<timestamp>.bak"
        fi
        echo "[DRY] 原子替换: $target_workflow"
        log_info "dry-run 完成，未写入 Finder 快捷操作"
        return 0
    fi

    mkdir -p "$SERVICES_DIR"
    TEMP_ROOT="$(mktemp -d "$SERVICES_DIR/.powershellScripts-quick-actions.XXXXXX")"
    staged_workflow="$TEMP_ROOT/$WORKFLOW_NAME"
    /usr/bin/ditto "$source_workflow" "$staged_workflow"
    configure_workflow "$staged_workflow"
    validate_workflow "$staged_workflow"

    if [ -d "$target_workflow" ] && diff -qr "$staged_workflow" "$target_workflow" >/dev/null 2>&1; then
        log_info "快捷操作内容未变化，无需覆盖: $target_workflow"
        return 0
    fi

    if [ -e "$target_workflow" ]; then
        backup_path="$(new_backup_path "$target_workflow")"
        log_warn "备份现有 workflow: $backup_path"
        mv "$target_workflow" "$backup_path"
    fi

    if ! mv "$staged_workflow" "$target_workflow"; then
        log_err "替换 workflow 失败: $target_workflow"
        if [ -n "$backup_path" ] && [ -e "$backup_path" ] && [ ! -e "$target_workflow" ]; then
            mv "$backup_path" "$target_workflow"
            log_warn "已恢复替换前 workflow"
        fi
        return 1
    fi

    validate_workflow "$target_workflow"
    log_info "已安装 Finder 快捷操作: $target_workflow"
    log_warn "如果 Finder 右键菜单未立即刷新，请重新打开 Finder 窗口或重启 Finder"
}

# 卸载仓库维护的 Finder 快捷操作。
# 入参：无。
# 返回值：成功或目标不存在返回 0，否则返回 1。
uninstall_quick_action() {
    local target_workflow="$SERVICES_DIR/$WORKFLOW_NAME"

    if [ ! -e "$target_workflow" ]; then
        log_info "快捷操作未安装: $target_workflow"
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY] 移除 workflow: $target_workflow"
        return 0
    fi

    rm -rf "$target_workflow"
    log_info "已移除 Finder 快捷操作: $target_workflow"
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

if [ "$UNATTENDED" = true ] && [ "$NON_INTERACTIVE" = true ]; then
    log_err 'unattended 与 non-interactive 不能同时使用'
    exit 2
fi
if [ "$UNINSTALL" = true ]; then
    uninstall_quick_action
else
    install_quick_action
fi
