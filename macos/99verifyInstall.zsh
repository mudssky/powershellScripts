#!/bin/zsh

# macOS 安装状态验证脚本。
# 功能：只读验证 Core/Full 安装合同，并输出文本或单文档 JSON。

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_NAME="$(basename "$0")"

PRESET="Core"
OUTPUT_FORMAT="text"
UNATTENDED=false
NON_INTERACTIVE=false
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
BLOCKED_COUNT=0

CORE_STEPS=(repo package-manager pwsh sources shell core-cli fonts profile-tools)
FULL_STEPS=(${CORE_STEPS[@]} full-apps platform-automation login-items desktop-integration)
VALID_STEPS=(${FULL_STEPS[@]})
SELECTED_STEPS=()
RESULT_STEPS=()
RESULT_STATUSES=()
RESULT_MESSAGES=()

# 显示脚本帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --preset Core|Full          验证预设，默认 Core
  --step <name>               只验证单个逻辑步骤
  --output-format text|json   输出文本或单文档 JSON
  --unattended                接受根编排器交互模式参数
  --non-interactive           接受根编排器交互模式参数
  -h, --help                  显示帮助

Steps:
  repo, package-manager, pwsh, sources, shell, core-cli, fonts,
  profile-tools, full-apps, platform-automation, login-items,
  desktop-integration
EOF
}

# 判断命令是否存在。
# 入参：$1 命令名称。
# 返回值：命令存在返回 0，否则返回 1。
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 判断数组是否包含指定值。
# 入参：$1 目标值；其余参数为候选值。
# 返回值：包含返回 0，否则返回 1。
contains_value() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# 记录一项验证结果并按输出模式打印。
# 入参：$1 步骤；$2 状态；$3 消息。
# 返回值：无。
record_result() {
    local step="$1"
    local result_status="$2"
    local message="$3"

    RESULT_STEPS+=("$step")
    RESULT_STATUSES+=("$result_status")
    RESULT_MESSAGES+=("$message")
    case "$result_status" in
        Pass) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        Warn) WARN_COUNT=$((WARN_COUNT + 1)) ;;
        Fail) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        Blocked) BLOCKED_COUNT=$((BLOCKED_COUNT + 1)) ;;
    esac

    if [ "$OUTPUT_FORMAT" = "text" ]; then
        printf '[%s] %s: %s\n' "${(U)result_status}" "$step" "$message"
    fi
}

# 记录通过项。
# 入参：$1 步骤；$2 消息。
# 返回值：无。
record_pass() { record_result "$1" Pass "$2"; }

# 记录提醒项，提醒不改变退出码。
# 入参：$1 步骤；$2 消息。
# 返回值：无。
record_warn() { record_result "$1" Warn "$2"; }

# 记录失败项。
# 入参：$1 步骤；$2 消息。
# 返回值：无。
record_fail() { record_result "$1" Fail "$2"; }

# 记录因权限或外部前置无法验证的项目。
# 入参：$1 步骤；$2 消息。
# 返回值：无。
record_blocked() { record_result "$1" Blocked "$2"; }

# 转义 JSON 字符串内容。
# 入参：$1 原始字符串。
# 返回值：向 stdout 输出不含外层引号的 JSON 字符串。
json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

# 输出单文档 JSON 汇总。
# 入参：$1 总体状态；$2 退出码。
# 返回值：无。
emit_json_summary() {
    local overall_status="$1"
    local exit_code="$2"
    local index
    local separator=""

    printf '{"Preset":"%s","Status":"%s","ExitCode":%d,' "$(json_escape "$PRESET")" "$overall_status" "$exit_code"
    printf '"Counts":{"Passed":%d,"Warned":%d,"Failed":%d,"Blocked":%d},' \
        "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT" "$BLOCKED_COUNT"
    printf '"Results":['
    for ((index = 1; index <= ${#RESULT_STEPS[@]}; index++)); do
        printf '%s{"Step":"%s","Status":"%s","Message":"%s"}' \
            "$separator" \
            "$(json_escape "${RESULT_STEPS[$index]}")" \
            "$(json_escape "${RESULT_STATUSES[$index]}")" \
            "$(json_escape "${RESULT_MESSAGES[$index]}")"
        separator=","
    done
    printf ']}\n'
}

# 验证仓库结构和安装注册表。
# 入参：无。
# 返回值：无，结果写入全局汇总。
check_repo() {
    local step="repo"
    local required_path
    for required_path in \
        "$REPO_ROOT/install.ps1" \
        "$REPO_ROOT/config/install/steps.psd1" \
        "$REPO_ROOT/profile/installer/apps-config.json" \
        "$REPO_ROOT/macos/INSTALL.md"; do
        if [ -e "$required_path" ]; then
            record_pass "$step" "存在: $required_path"
        else
            record_fail "$step" "缺失: $required_path"
        fi
    done

    if command_exists git && git -C "$REPO_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
        record_pass "$step" "Git 可解析仓库根目录"
    else
        record_fail "$step" "无法解析 Git 仓库根目录"
    fi
}

# 验证 Homebrew 命令和 prefix。
# 入参：无。
# 返回值：无，结果写入全局汇总。
check_package_manager() {
    local step="package-manager"
    if ! command_exists brew; then
        record_fail "$step" "brew 不可用；运行 macos/01installHomebrew.zsh"
        return
    fi
    record_pass "$step" "brew 命令可用"

    if brew --prefix >/dev/null 2>&1; then
        record_pass "$step" "brew prefix 可读取"
    else
        record_fail "$step" "brew --prefix 失败"
    fi
}

# 验证 PowerShell 7。
# 入参：无。
# 返回值：无，结果写入全局汇总。
check_pwsh() {
    local step="pwsh"
    local major_version
    if ! command_exists pwsh; then
        record_fail "$step" "pwsh 不可用；运行 macos/02installPowerShell.zsh"
        return
    fi

    major_version="$(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>/dev/null)"
    if [[ "$major_version" == <-> ]] && [ "$major_version" -ge 7 ]; then
        record_pass "$step" "PowerShell $major_version 可无 Profile 启动"
    else
        record_fail "$step" "PowerShell 7 基线未满足"
    fi
}

# 只读检查 package source 引擎和当前事务状态。
# 入参：无。
# 返回值：无，结果写入全局汇总。
check_sources() {
    local step="sources"
    local source_engine="$REPO_ROOT/scripts/pwsh/misc/Switch-Mirrors.ps1"
    local source_output
    local source_exit

    if [ ! -f "$source_engine" ]; then
        record_fail "$step" "source 引擎缺失: $source_engine"
        return
    fi
    if ! command_exists pwsh; then
        record_blocked "$step" "缺少 pwsh，无法读取 source 状态"
        return
    fi

    source_output="$(pwsh -NoProfile -File "$source_engine" -Action Status -OutputFormat Json 2>/dev/null)"
    source_exit=$?
    if [ "$source_exit" -eq 0 ] && [ -n "$source_output" ]; then
        record_pass "$step" "source 状态可读取"
    elif [ "$source_exit" -eq 10 ]; then
        record_blocked "$step" "source 状态存在 drift、orphan 或外部前置"
    else
        record_fail "$step" "source 状态读取失败，退出码 $source_exit"
    fi

    if [ -f "$REPO_ROOT/shell/shared.d/package-sources.sh" ]; then
        record_pass "$step" "受管 source shell loader 存在"
    else
        record_fail "$step" "受管 source shell loader 缺失"
    fi
}

# 验证 zsh loader 和仓库托管片段链接。
# 入参：无。
# 返回值：无，结果写入全局汇总。
check_shell() {
    local step="shell"
    local zshrc="$HOME/.zshrc"
    local snippet_dir="$HOME/.bashrc.d"
    local link_path
    local managed_link_found=false

    if [ -f "$zshrc" ] && grep -Fq "Load modular configuration files from ~/.bashrc.d" "$zshrc"; then
        record_pass "$step" "~/.zshrc 包含模块 loader"
    else
        record_fail "$step" "~/.zshrc 未部署模块 loader；运行 macos/04deployShellConfig.zsh"
    fi

    if [ ! -d "$snippet_dir" ]; then
        record_fail "$step" "~/.bashrc.d 不存在"
        return
    fi

    for link_path in "$snippet_dir"/*(N); do
        [ -L "$link_path" ] || continue
        case "$(readlink "$link_path" 2>/dev/null)" in
            "$REPO_ROOT/shell/shared.d/"*|"$REPO_ROOT/shell/zsh.d/"*)
                managed_link_found=true
                break
                ;;
        esac
    done
    if [ "$managed_link_found" = true ]; then
        record_pass "$step" "~/.bashrc.d 包含仓库托管链接"
    else
        record_fail "$step" "~/.bashrc.d 没有指向当前仓库的托管链接"
    fi
}

# 调用 PowerShell 只读 helper，并合并逐项结果。
# 入参：$1 core-cli、fonts、full-apps 或 profile-tools。
# 返回值：无，结果写入全局汇总。
check_power_shell_state() {
    local step="$1"
    local helper="$REPO_ROOT/macos/pwsh/Test-InstallState.ps1"
    local helper_output
    local helper_exit
    local result_status
    local name
    local message

    if ! command_exists pwsh; then
        record_blocked "$step" "缺少 pwsh，已跳过依赖应用清单的检查"
        return
    fi
    if [ ! -f "$helper" ]; then
        record_fail "$step" "验证 helper 缺失: $helper"
        return
    fi

    helper_output="$(pwsh -NoProfile -File "$helper" -Step "$step" -OutputFormat Tsv 2>&1)"
    helper_exit=$?
    if [ "$helper_exit" -ne 0 ]; then
        record_fail "$step" "验证 helper 执行失败: $helper_output"
        return
    fi

    while IFS=$'\t' read -r result_status name message; do
        [ -n "$result_status" ] || continue
        case "$result_status" in
            Pass) record_pass "$step" "$name: $message" ;;
            Warn) record_warn "$step" "$name: $message" ;;
            Fail) record_fail "$step" "$name: $message" ;;
            Blocked) record_blocked "$step" "$name: $message" ;;
            *) record_fail "$step" "helper 返回未知状态 $result_status: $name $message" ;;
        esac
    done <<< "$helper_output"
}

# 判断当前用户登录项是否包含指定 App。
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
            if name of loginItem is itemName then return "true"
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

# 验证 Hammerspoon 部署文件与动态 manifest。
# 入参：无。
# 返回值：无，结果写入全局汇总。
check_platform_automation() {
    local step="platform-automation"
    local config_dir="$HOME/.hammerspoon"
    local manifest_file="$config_dir/.powershellscripts-hammerspoon.manifest"
    local source_file
    local relative_path
    local target_file

    for target_file in "$config_dir/init.lua" "$config_dir/config.lua" "$config_dir/config.local.lua"; do
        if [ -f "$target_file" ]; then
            record_pass "$step" "存在: $target_file"
        else
            record_fail "$step" "缺失: $target_file；运行 macos/09deployHammerspoon.zsh"
        fi
    done
    if [ ! -f "$manifest_file" ]; then
        record_fail "$step" "Hammerspoon manifest 缺失"
        return
    fi

    while IFS= read -r source_file; do
        [ -n "$source_file" ] || continue
        relative_path="${source_file#$REPO_ROOT/macos/hammerspoon/}"
        target_file="$config_dir/scripts/$relative_path"
        if [ -f "$target_file" ] && grep -Fxq "scripts/$relative_path" "$manifest_file"; then
            record_pass "$step" "已托管: scripts/$relative_path"
        else
            record_fail "$step" "插件或 manifest 条目缺失: scripts/$relative_path"
        fi
    done < <(find "$REPO_ROOT/macos/hammerspoon/plugins" -type f \( -name '*.lua' -o -name '*.zsh' \) | sort)
}

# 验证 Full 预设登录项。
# 入参：无。
# 返回值：无，结果写入全局汇总。
check_login_items() {
    local step="login-items"
    local item_name
    local item_status
    if ! command_exists osascript; then
        record_blocked "$step" "osascript 不可用，无法读取登录项"
        return
    fi

    for item_name in Hammerspoon Mos; do
        item_status=0
        login_item_exists "$item_name" || item_status=$?
        if [ "$item_status" -eq 0 ]; then
            record_pass "$step" "$item_name 登录项存在"
        elif [ "$item_status" -eq 2 ]; then
            record_blocked "$step" "无法读取登录项，请授予 System Events Automation 权限"
        else
            record_fail "$step" "$item_name 登录项缺失；运行 macos/10configureLoginItems.zsh"
        fi
    done
}

# 验证 Finder 快捷操作及 runner/action 分层。
# 入参：无。
# 返回值：无，结果写入全局汇总。
check_desktop_integration() {
    local step="desktop-integration"
    local workflow_name="Fix App Open Issue.workflow"
    local installed_workflow="$HOME/Library/Services/$workflow_name"
    local document_wflow="$installed_workflow/Contents/document.wflow"
    local info_plist="$installed_workflow/Contents/Info.plist"
    local runner_path="$REPO_ROOT/macos/quick-actions/run.zsh"
    local action_path="$REPO_ROOT/macos/quick-actions/fix-app-open-issue.zsh"
    local command_string=""

    for required_path in "$runner_path" "$action_path"; do
        if [ -f "$required_path" ]; then
            record_pass "$step" "存在: $required_path"
        else
            record_fail "$step" "缺失: $required_path"
        fi
    done
    if [ ! -d "$installed_workflow" ]; then
        record_fail "$step" "快捷操作未安装；运行 macos/11installQuickActions.zsh"
        return
    fi
    if [ ! -x /usr/bin/plutil ]; then
        record_blocked "$step" "plutil 不可用，无法校验 workflow"
        return
    fi

    if /usr/bin/plutil -lint "$info_plist" >/dev/null 2>&1 && /usr/bin/plutil -lint "$document_wflow" >/dev/null 2>&1; then
        record_pass "$step" "已安装 workflow plist 有效"
    else
        record_fail "$step" "已安装 workflow plist 无效"
        return
    fi
    if command_string="$(/usr/bin/plutil -extract actions.0.action.ActionParameters.COMMAND_STRING raw "$document_wflow" 2>/dev/null)" \
        && [[ "$command_string" == *"$runner_path"* ]] \
        && [[ "$command_string" == *"fix-app-open-issue"* ]]; then
        record_pass "$step" "workflow 指向当前仓库 runner 和 action"
    else
        record_fail "$step" "workflow 未指向当前仓库 runner/action"
    fi
}

# 执行指定逻辑步骤的验证函数。
# 入参：$1 逻辑步骤 ID。
# 返回值：无，结果写入全局汇总。
run_step() {
    local step="$1"
    case "$step" in
        repo) check_repo ;;
        package-manager) check_package_manager ;;
        pwsh) check_pwsh ;;
        sources) check_sources ;;
        shell) check_shell ;;
        core-cli|fonts|profile-tools|full-apps) check_power_shell_state "$step" ;;
        platform-automation) check_platform_automation ;;
        login-items) check_login_items ;;
        desktop-integration) check_desktop_integration ;;
        *) record_fail "$step" "未知验证步骤" ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --preset)
            [ $# -ge 2 ] || { echo "--preset 需要一个值" >&2; exit 2; }
            PRESET="$2"
            shift 2
            ;;
        --step)
            [ $# -ge 2 ] || { echo "--step 需要一个值" >&2; exit 2; }
            SELECTED_STEPS=("$2")
            shift 2
            ;;
        --output-format)
            [ $# -ge 2 ] || { echo "--output-format 需要一个值" >&2; exit 2; }
            OUTPUT_FORMAT="${(L)2}"
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
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$PRESET" != "Core" ] && [ "$PRESET" != "Full" ]; then
    echo "不支持的 preset: $PRESET" >&2
    exit 2
fi
if [ "$OUTPUT_FORMAT" != "text" ] && [ "$OUTPUT_FORMAT" != "json" ]; then
    echo "不支持的 output format: $OUTPUT_FORMAT" >&2
    exit 2
fi
if [ "$UNATTENDED" = true ] && [ "$NON_INTERACTIVE" = true ]; then
    echo "unattended 与 non-interactive 不能同时使用" >&2
    exit 2
fi
if [ ${#SELECTED_STEPS[@]} -gt 0 ]; then
    if ! contains_value "${SELECTED_STEPS[1]}" "${VALID_STEPS[@]}"; then
        echo "未知验证步骤: ${SELECTED_STEPS[1]}" >&2
        exit 2
    fi
else
    if [ "$PRESET" = "Full" ]; then
        SELECTED_STEPS=(${FULL_STEPS[@]})
    else
        SELECTED_STEPS=(${CORE_STEPS[@]})
    fi
fi

if [ "$OUTPUT_FORMAT" = "text" ]; then
    echo "macOS install verification"
    echo "Preset: $PRESET"
    echo "Repository: $REPO_ROOT"
    echo
fi

for step in "${SELECTED_STEPS[@]}"; do
    run_step "$step"
done

overall_status="Succeeded"
exit_code=0
if [ "$FAIL_COUNT" -gt 0 ]; then
    overall_status="Failed"
    exit_code=1
elif [ "$BLOCKED_COUNT" -gt 0 ]; then
    overall_status="Blocked"
    exit_code=10
fi

if [ "$OUTPUT_FORMAT" = "json" ]; then
    emit_json_summary "$overall_status" "$exit_code"
else
    echo
    echo "Summary: $PASS_COUNT passed, $WARN_COUNT warned, $FAIL_COUNT failed, $BLOCKED_COUNT blocked"
fi
exit "$exit_code"
