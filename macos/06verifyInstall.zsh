#!/bin/zsh

# macOS 安装状态验证脚本。
# 只读取当前机器状态，不执行安装、不写入用户配置、不启动 GUI 应用。

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_NAME="$(basename "$0")"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

VALID_STEPS=(repo brew pwsh shell apps hammerspoon login-items quick-actions)
SELECTED_STEPS=("${VALID_STEPS[@]}")

# 显示帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --step <name>  只验证单个阶段：repo, brew, pwsh, shell, apps, hammerspoon, login-items, quick-actions
  -h, --help     显示帮助

Examples:
  zsh macos/06verifyInstall.zsh
  zsh macos/06verifyInstall.zsh --step brew
EOF
}

# 输出通过项并累计计数。
# 入参：$1 检查阶段；$2 检查说明。
# 返回值：无。
record_pass() {
    local step="$1"
    local message="$2"
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "[PASS] $step: $message"
}

# 输出提醒项并累计计数。
# 入参：$1 检查阶段；$2 检查说明。
# 返回值：无。
record_warn() {
    local step="$1"
    local message="$2"
    WARN_COUNT=$((WARN_COUNT + 1))
    echo "[WARN] $step: $message"
}

# 输出失败项并累计计数。
# 入参：$1 检查阶段；$2 检查说明。
# 返回值：无。
record_fail() {
    local step="$1"
    local message="$2"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[FAIL] $step: $message"
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

# 解析已存在路径的物理路径。
# 入参：$1 路径。
# 返回值：成功时输出规范化路径并返回 0，否则返回 1。
canonical_existing_path() {
    local path="$1"
    if [ ! -e "$path" ]; then
        return 1
    fi

    local dir
    local base
    dir="$(dirname "$path")"
    base="$(basename "$path")"
    printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
}

# 判断 symlink 是否最终指向指定文件。
# 入参：$1 symlink 路径；$2 期望目标路径。
# 返回值：指向期望文件返回 0，否则返回 1。
symlink_points_to() {
    local link_path="$1"
    local expected_path="$2"
    local raw_target
    local candidate_path
    local actual_canonical
    local expected_canonical

    raw_target="$(readlink "$link_path")" || return 1
    if [[ "$raw_target" = /* ]]; then
        candidate_path="$raw_target"
    else
        candidate_path="$(dirname "$link_path")/$raw_target"
    fi

    actual_canonical="$(canonical_existing_path "$candidate_path")" || return 1
    expected_canonical="$(canonical_existing_path "$expected_path")" || return 1
    [ "$actual_canonical" = "$expected_canonical" ]
}

# 判断 Homebrew Cask 或常见应用目录中是否存在 GUI 应用。
# 入参：$1 cask 名称；$2 App bundle 名称，不含 .app。
# 返回值：找到返回 0，否则返回 1。
is_cask_or_app_installed() {
    local cask_name="$1"
    local app_name="$2"

    if command_exists brew && brew list --cask "$cask_name" >/dev/null 2>&1; then
        return 0
    fi

    open -Ra "$app_name" >/dev/null 2>&1 && return 0

    [ -d "/Applications/$app_name.app" ] && return 0
    [ -d "$HOME/Applications/$app_name.app" ] && return 0

    return 1
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

# 验证当前仓库结构。
# 入参：无。
# 返回值：无。失败项通过全局计数记录。
check_repo() {
    local step="repo"

    if [ -f "$REPO_ROOT/macos/INSTALL.md" ]; then
        record_pass "$step" "found macos/INSTALL.md"
    else
        record_fail "$step" "macos/INSTALL.md not found under $REPO_ROOT"
    fi

    if [ -f "$REPO_ROOT/profile/installer/apps-config.json" ]; then
        record_pass "$step" "found profile/installer/apps-config.json"
    else
        record_fail "$step" "profile/installer/apps-config.json not found under $REPO_ROOT"
    fi

    if [ -e "$REPO_ROOT/.git" ]; then
        record_pass "$step" "repository metadata is present"
    elif command_exists git && git -C "$REPO_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
        record_pass "$step" "git can resolve repository root"
    else
        record_fail "$step" "git repository metadata not found"
    fi
}

# 验证 Homebrew。
# 入参：无。
# 返回值：无。失败项通过全局计数记录。
check_brew() {
    local step="brew"

    if command_exists brew; then
        record_pass "$step" "brew command is available"
    else
        record_fail "$step" "brew command not found; run zsh macos/01installHomeBrew.sh"
        return
    fi

    if brew --prefix >/dev/null 2>&1; then
        record_pass "$step" "brew prefix is readable"
    else
        record_fail "$step" "brew --prefix failed"
    fi
}

# 验证 PowerShell。
# 入参：无。
# 返回值：无。失败项通过全局计数记录。
check_pwsh() {
    local step="pwsh"

    if command_exists pwsh; then
        record_pass "$step" "pwsh command is available"
    else
        record_fail "$step" "pwsh command not found; run zsh macos/02installPowerShell.sh"
        return
    fi

    if pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' >/dev/null 2>&1; then
        record_pass "$step" "PowerShell starts without loading profile"
    else
        record_fail "$step" "pwsh failed to start with -NoProfile"
    fi
}

# 验证 shell 配置部署结果。
# 入参：无。
# 返回值：无。失败项通过全局计数记录。
check_shell() {
    local step="shell"
    local zshrc="$HOME/.zshrc"
    local snippet_dir="$HOME/.bashrc.d"
    local managed_link_found=false

    if [ ! -e "$zshrc" ]; then
        record_fail "$step" "~/.zshrc not found; run zsh macos/03deployShellConfig.sh"
    elif grep -Fq "Load modular configuration files from ~/.bashrc.d" "$zshrc"; then
        record_pass "$step" "~/.zshrc contains modular loader"
    else
        record_fail "$step" "~/.zshrc does not contain modular loader"
    fi

    if [ -d "$snippet_dir" ]; then
        record_pass "$step" "~/.bashrc.d exists"
    else
        record_fail "$step" "~/.bashrc.d not found; run zsh macos/03deployShellConfig.sh"
        return
    fi

    local link_path
    local target_path
    for link_path in "$snippet_dir"/*(N); do
        [ -L "$link_path" ] || continue
        target_path="$(readlink "$link_path")" || continue
        if [[ "$target_path" = "$REPO_ROOT/shell/shared.d/"* ]] || [[ "$target_path" = "$REPO_ROOT/shell/zsh.d/"* ]]; then
            managed_link_found=true
            break
        fi
    done

    if [ "$managed_link_found" = true ]; then
        record_pass "$step" "~/.bashrc.d contains repository-managed shell snippets"
    else
        record_fail "$step" "~/.bashrc.d has no symlink to this repository's shell snippets"
    fi
}

# 验证关键 macOS 应用。
# 入参：无。
# 返回值：无。失败项通过全局计数记录。
check_apps() {
    local step="apps"

    if ! command_exists brew; then
        record_fail "$step" "brew command not found; run zsh macos/01installHomeBrew.sh first"
        return
    fi

    if is_cask_or_app_installed "hammerspoon" "Hammerspoon"; then
        record_pass "$step" "Hammerspoon is installed"
    else
        record_fail "$step" "Hammerspoon not found; run pwsh macos/04installApps.ps1"
    fi

    if command_exists starship; then
        record_pass "$step" "starship command is available"
    else
        record_fail "$step" "starship command not found; run pwsh macos/04installApps.ps1"
    fi

    if command_exists blueutil; then
        record_pass "$step" "blueutil command is available"
    else
        record_fail "$step" "blueutil command not found; run pwsh macos/04installApps.ps1"
    fi

    if is_cask_or_app_installed "iterm2" "iTerm"; then
        record_pass "$step" "iTerm is installed"
    else
        record_warn "$step" "iTerm not found"
    fi

    if is_cask_or_app_installed "keka" "Keka"; then
        record_pass "$step" "Keka is installed"
    else
        record_warn "$step" "Keka not found"
    fi

    if is_cask_or_app_installed "maccy" "Maccy"; then
        record_pass "$step" "Maccy is installed"
    else
        record_warn "$step" "Maccy not found"
    fi

    if is_cask_or_app_installed "mos" "Mos"; then
        record_pass "$step" "Mos is installed"
    else
        record_fail "$step" "Mos not found; run pwsh macos/04installApps.ps1"
    fi
}

# 验证 Hammerspoon 配置部署结果。
# 入参：无。
# 返回值：无。失败项通过全局计数记录。
check_hammerspoon() {
    local step="hammerspoon"
    local config_dir="$HOME/.hammerspoon"
    local manifest_file="$config_dir/.powershellscripts-hammerspoon.manifest"
    local required_files=(
        "$config_dir/init.lua"
        "$config_dir/config.lua"
        "$config_dir/config.local.lua"
        "$config_dir/scripts/plugins/win-hotkeys/plugin.lua"
        "$config_dir/scripts/plugins/power-lid-sleep/plugin.lua"
        "$config_dir/scripts/plugins/power-lid-sleep/app_guard.lua"
        "$config_dir/scripts/plugins/power-lid-sleep/bluetooth_guard.lua"
        "$config_dir/scripts/plugins/power-lid-sleep/lid_state.lua"
        "$config_dir/scripts/plugins/power-lid-sleep/process_guard.lua"
    )
    local required_manifest_entries=(
        "init.lua"
        "config.lua"
        "scripts/plugins/win-hotkeys/plugin.lua"
        "scripts/plugins/power-lid-sleep/plugin.lua"
        "scripts/plugins/power-lid-sleep/app_guard.lua"
        "scripts/plugins/power-lid-sleep/bluetooth_guard.lua"
        "scripts/plugins/power-lid-sleep/lid_state.lua"
        "scripts/plugins/power-lid-sleep/process_guard.lua"
    )

    if is_cask_or_app_installed "hammerspoon" "Hammerspoon"; then
        record_pass "$step" "Hammerspoon app is installed"
    else
        record_fail "$step" "Hammerspoon app not found; run pwsh macos/04installApps.ps1"
    fi

    local file_path
    for file_path in "${required_files[@]}"; do
        if [ -f "$file_path" ]; then
            record_pass "$step" "$file_path exists"
        else
            record_fail "$step" "$file_path not found; run zsh macos/05deployHammerspoon.sh"
        fi
    done

    if [ -f "$manifest_file" ]; then
        record_pass "$step" "$manifest_file exists"
    else
        record_fail "$step" "$manifest_file not found; run zsh macos/05deployHammerspoon.sh"
        return
    fi

    local manifest_entry
    for manifest_entry in "${required_manifest_entries[@]}"; do
        if grep -Fxq "$manifest_entry" "$manifest_file"; then
            record_pass "$step" "manifest contains $manifest_entry"
        else
            record_fail "$step" "manifest missing $manifest_entry"
        fi
    done
}

# 验证关键 GUI 工具登录启动项。
# 入参：无。
# 返回值：无。失败项通过全局计数记录。
check_login_items() {
    local step="login-items"
    local item_name
    local required_items=("Hammerspoon" "Mos")
    local login_status=0

    if ! command_exists osascript; then
        record_fail "$step" "osascript command not found"
        return
    fi

    for item_name in "${required_items[@]}"; do
        login_status=0
        login_item_exists "$item_name" || login_status=$?
        if [ "$login_status" -eq 0 ]; then
            record_pass "$step" "$item_name login item exists"
        else
            case "$login_status" in
                2)
                    record_fail "$step" "cannot read login items; grant Automation permission for System Events"
                    ;;
                *)
                    record_fail "$step" "$item_name login item not found; run zsh macos/07configureLoginItems.zsh"
                    ;;
            esac
        fi
    done
}

# 验证 Finder 右键动作安装结果。
# 入参：无。
# 返回值：无。失败项通过全局计数记录。
check_quick_actions() {
    local step="quick-actions"
    local services_dir="$HOME/Library/Services"
    local workflow_name="Fix App Open Issue.workflow"
    local source_workflow="$REPO_ROOT/macos/quick-actions/$workflow_name"
    local installed_workflow="$services_dir/$workflow_name"
    local runner_path="$REPO_ROOT/macos/quick-actions/run.zsh"
    local script_path="$REPO_ROOT/macos/quick-actions/fix-app-open-issue.zsh"
    local info_plist="$installed_workflow/Contents/Info.plist"
    local document_wflow="$installed_workflow/Contents/document.wflow"
    local command_string=""

    if [ -f "$runner_path" ]; then
        record_pass "$step" "found quick action runner"
    else
        record_fail "$step" "run.zsh not found under macos/quick-actions"
    fi

    if [ -f "$script_path" ]; then
        record_pass "$step" "found fix-app-open-issue.zsh"
    else
        record_fail "$step" "fix-app-open-issue.zsh not found under macos/quick-actions"
    fi

    if [ -d "$source_workflow" ]; then
        record_pass "$step" "found repository workflow template"
    else
        record_fail "$step" "repository workflow template not found; check macos/quick-actions"
    fi

    if [ -d "$installed_workflow" ]; then
        record_pass "$step" "$installed_workflow exists"
    else
        record_fail "$step" "$installed_workflow not found; run zsh macos/08installQuickActions.zsh"
        return
    fi

    if [ -f "$info_plist" ] && /usr/bin/plutil -lint "$info_plist" >/dev/null 2>&1; then
        record_pass "$step" "installed Info.plist is valid"
    else
        record_fail "$step" "installed Info.plist missing or invalid"
    fi

    if [ -f "$document_wflow" ] && /usr/bin/plutil -lint "$document_wflow" >/dev/null 2>&1; then
        record_pass "$step" "installed document.wflow is valid"
    else
        record_fail "$step" "installed document.wflow missing or invalid"
    fi

    if command_string="$(/usr/bin/plutil -extract actions.0.action.ActionParameters.COMMAND_STRING raw "$document_wflow" 2>/dev/null)" \
        && [[ "$command_string" == *"$runner_path"* ]] \
        && [[ "$command_string" == *"fix-app-open-issue"* ]]; then
        record_pass "$step" "workflow points to repository runner and action"
    else
        record_fail "$step" "workflow does not point to $runner_path fix-app-open-issue; run zsh macos/08installQuickActions.zsh"
    fi
}

# 验证指定阶段。
# 入参：$1 阶段名称。
# 返回值：无。失败项通过全局计数记录。
run_step() {
    local step="$1"

    case "$step" in
        repo) check_repo ;;
        brew) check_brew ;;
        pwsh) check_pwsh ;;
        shell) check_shell ;;
        apps) check_apps ;;
        hammerspoon) check_hammerspoon ;;
        login-items) check_login_items ;;
        quick-actions) check_quick_actions ;;
        *)
            record_fail "$step" "unknown verification step"
            ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --step)
            if [ $# -lt 2 ]; then
                echo "[FAIL] args: --step requires a value" >&2
                usage >&2
                exit 2
            fi

            if ! contains_value "$2" "${VALID_STEPS[@]}"; then
                echo "[FAIL] args: unknown step '$2'" >&2
                usage >&2
                exit 2
            fi

            SELECTED_STEPS=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[FAIL] args: unknown argument '$1'" >&2
            usage >&2
            exit 2
            ;;
    esac
done

echo "macOS install verification"
echo "Repository: $REPO_ROOT"
echo

for step in "${SELECTED_STEPS[@]}"; do
    run_step "$step"
done

echo
echo "Summary: $PASS_COUNT passed, $WARN_COUNT warned, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi

exit 0
