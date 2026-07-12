#!/usr/bin/env zsh

set -uo pipefail

APPLY=false
OUTPUT_FORMAT='text'
SSH_PORT=22
RESULTS=()
MANUAL_STEPS=()
EXIT_CODE=0
STATUS='Preview'
TAILSCALE_IP=''
PYTHON_PATH=''
SCRIPT_DIR="${0:A:h}"

# 功能：输出脚本帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: prepare-ansible-host.zsh [options]

Options:
  --apply                     自动安装和配置缺失前置
  --output-format text|json   输出格式，默认 text
  --ssh-port <port>           SSH 端口，默认 22
  -h, --help                  显示帮助
EOF
}

# 功能：追加结构化结果项。
# 参数：$1 名称，$2 状态，$3 退出码，$4 changed 布尔值，$5 消息。
# 返回：0。
add_result() {
    RESULTS+=("$1"$'\x1f'"$2"$'\x1f'"$3"$'\x1f'"$4"$'\x1f'"$5")
}

# 功能：追加需要用户完成的操作步骤。
# 参数：$1 名称，$2 位置，$3 操作，$4 验证命令，$5 原因。
# 返回：0。
add_manual_step() {
    MANUAL_STEPS+=("$1"$'\x1f'"$2"$'\x1f'"$3"$'\x1f'"$4"$'\x1f'"$5")
}

# 功能：转义 JSON 字符串。
# 参数：$1 原始字符串。
# 返回：0 并输出转义后的字符串。
json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    print -rn -- "$value"
}

# 功能：定位 Homebrew 可执行文件。
# 参数：无。
# 返回：0 并输出路径，1 未找到。
find_brew() {
    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
    fi
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$candidate" ]]; then
            print -r -- "$candidate"
            return 0
        fi
    done
    return 1
}

# 功能：定位 Tailscale CLI。
# 参数：无。
# 返回：0 并输出路径，1 未找到。
find_tailscale() {
    if command -v tailscale >/dev/null 2>&1; then
        command -v tailscale
        return 0
    fi
    local candidate
    for candidate in \
        /Applications/Tailscale.app/Contents/MacOS/Tailscale \
        /Applications/Tailscale.app/Contents/MacOS/tailscale \
        /Applications/Tailscale.app/Contents/Macos/tailscale; do
        if [[ -x "$candidate" ]]; then
            print -r -- "$candidate"
            return 0
        fi
    done
    return 1
}

# 功能：获得一次 sudo 认证用于后续系统变更。
# 参数：无。
# 返回：0 成功，10 用户取消或无 sudo 权限。
prepare_sudo() {
    if [[ "$APPLY" != true ]]; then
        return 0
    fi
    sudo -v || return 10
}

# 功能：确保 Homebrew 可用。
# 参数：无。
# 返回：0 已存在或安装成功，1 安装失败。
ensure_homebrew() {
    local brew_path
    if brew_path="$(find_brew)"; then
        eval "$("$brew_path" shellenv)"
        add_result 'Homebrew' 'AlreadyPresent' 0 false "Homebrew: $(brew --prefix)"
        return 0
    fi
    if [[ "$APPLY" != true ]]; then
        add_result 'Homebrew' 'Preview' 0 false 'zsh macos/01installHomebrew.zsh --unattended'
        return 0
    fi
    if ! zsh "$SCRIPT_DIR/../01installHomebrew.zsh" --unattended; then
        return 1
    fi
    brew_path="$(find_brew)" || return 1
    eval "$("$brew_path" shellenv)"
    add_result 'Homebrew' 'Succeeded' 0 true "Homebrew 已安装: $(brew --prefix)"
    return 0
}

# 功能：确保 Python 3 已安装。
# 参数：无。
# 返回：0 已存在或安装成功，1 安装失败。
ensure_python() {
    if [[ -n "${POWERSHELL_SCRIPTS_ANSIBLE_PREP_PYTHON_PATH:-}" ]]; then
        PYTHON_PATH="$POWERSHELL_SCRIPTS_ANSIBLE_PREP_PYTHON_PATH"
        add_result 'Python3' 'AlreadyPresent' 0 false "Python 3: $PYTHON_PATH"
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_PATH="$(command -v python3)"
        add_result 'Python3' 'AlreadyPresent' 0 false "Python 3: $PYTHON_PATH"
        return 0
    fi
    if [[ "$APPLY" != true ]]; then
        add_result 'Python3' 'Preview' 0 false 'brew install python'
        return 0
    fi
    brew install python || return 1
    PYTHON_PATH="$(command -v python3 2>/dev/null || true)"
    [[ -n "$PYTHON_PATH" ]] || return 1
    add_result 'Python3' 'Succeeded' 0 true "已安装 Python 3: $PYTHON_PATH"
    return 0
}

# 功能：确保 Tailscale App 已安装。
# 参数：无。
# 返回：0 已存在或安装成功，1 安装失败。
ensure_tailscale() {
    local tailscale_path
    if [[ "${POWERSHELL_SCRIPTS_ANSIBLE_PREP_TAILSCALE_INSTALLED:-}" == '1' ]] || tailscale_path="$(find_tailscale)"; then
        add_result 'TailscaleInstall' 'AlreadyPresent' 0 false "Tailscale: ${tailscale_path:-fixture}"
        return 0
    fi
    if [[ "$APPLY" != true ]]; then
        add_result 'TailscaleInstall' 'Preview' 0 false 'brew install --cask tailscale && open -a Tailscale'
        return 0
    fi
    brew install --cask tailscale || return 1
    open -a Tailscale >/dev/null 2>&1 || true
    add_result 'TailscaleInstall' 'Succeeded' 0 true '已安装并打开 Tailscale App'
    return 0
}

# 功能：检测 Remote Login 是否已启用。
# 参数：无。
# 返回：0 已启用，1 未启用或无法读取。
remote_login_enabled() {
    if [[ "${POWERSHELL_SCRIPTS_ANSIBLE_PREP_REMOTE_LOGIN:-}" == '1' ]]; then
        return 0
    fi
    if [[ "${POWERSHELL_SCRIPTS_ANSIBLE_PREP_REMOTE_LOGIN:-}" == '0' ]]; then
        return 1
    fi
    /usr/sbin/systemsetup -getremotelogin 2>/dev/null | grep -qi ': On$'
}

# 功能：确保 macOS Remote Login 已启用。
# 参数：无。
# 返回：0 已满足或启用成功，1 普通失败，10 系统权限阻断。
ensure_remote_login() {
    if remote_login_enabled; then
        add_result 'RemoteLogin' 'AlreadyPresent' 0 false 'macOS Remote Login 已启用'
        return 0
    fi
    if [[ "$APPLY" != true ]]; then
        add_result 'RemoteLogin' 'Preview' 0 false 'sudo systemsetup -setremotelogin on'
        return 0
    fi
    local output
    if output="$(sudo /usr/sbin/systemsetup -setremotelogin on 2>&1)"; then
        add_result 'RemoteLogin' 'Succeeded' 0 true '已启用 macOS Remote Login'
        return 0
    fi
    add_result 'RemoteLogin' 'Blocked' 10 false "systemsetup 无法启用 Remote Login: $output"
    add_manual_step 'GrantFullDiskAccess' '系统设置 > 隐私与安全性 > 完全磁盘访问权限' \
        '为当前使用的 Terminal、iTerm2 或 VS Code 授予完全磁盘访问权限，然后重新打开终端' \
        'sudo systemsetup -getremotelogin' \
        '较新的 macOS 可能阻止未获完全磁盘访问权限的 systemsetup 修改 Remote Login'
    add_manual_step 'EnableRemoteLogin' '新打开的终端' 'sudo systemsetup -setremotelogin on' \
        'sudo systemsetup -getremotelogin' '完成权限授权后重新执行系统命令'
    return 10
}

# 功能：发现唯一 Tailscale IPv4。
# 参数：无。
# 返回：0 并设置 TAILSCALE_IP，1 未登录或地址无效。
detect_tailscale_ip() {
    local candidate="${POWERSHELL_SCRIPTS_ANSIBLE_PREP_TAILSCALE_IP:-}"
    local tailscale_path
    if [[ -z "$candidate" ]] && tailscale_path="$(find_tailscale)"; then
        candidate="$("$tailscale_path" ip -4 2>/dev/null | sed -n '1p')"
    fi
    if [[ "$candidate" =~ '^100\.([0-9]+)\.' ]]; then
        local second_octet="${match[1]}"
        if (( second_octet >= 64 && second_octet <= 127 )); then
            TAILSCALE_IP="$candidate"
            return 0
        fi
    fi
    return 1
}

# 功能：在 macOS Application Firewall 开启时确保 sshd wrapper 未被阻止。
# 参数：无。
# 返回：0 已满足或配置成功，1 配置失败。
ensure_firewall_access() {
    local firewall_tool='/usr/libexec/ApplicationFirewall/socketfilterfw'
    local ssh_wrapper='/usr/libexec/sshd-keygen-wrapper'
    if [[ ! -x "$firewall_tool" ]] || ! "$firewall_tool" --getglobalstate 2>/dev/null | grep -qi 'enabled'; then
        add_result 'FirewallRule' 'Skipped' 0 false 'macOS Application Firewall 未启用或不可用；不改变全局状态'
        return 0
    fi
    if [[ "$APPLY" != true ]]; then
        add_result 'FirewallRule' 'Preview' 0 false "sudo $firewall_tool --add $ssh_wrapper && sudo $firewall_tool --unblockapp $ssh_wrapper"
        return 0
    fi
    sudo "$firewall_tool" --add "$ssh_wrapper" >/dev/null 2>&1 || return 1
    sudo "$firewall_tool" --unblockapp "$ssh_wrapper" >/dev/null 2>&1 || return 1
    add_result 'FirewallRule' 'Succeeded' 0 true '已允许系统 SSH wrapper；未改变防火墙全局开关'
    return 0
}

# 功能：按统一结构输出 Text 或 Json。
# 参数：$1 host，$2 user，$3 rerun command。
# 返回：0。
write_document() {
    local host_name="$1" user_name="$2" rerun_command="$3"
    if [[ "$OUTPUT_FORMAT" == 'json' ]]; then
        printf '{"SchemaVersion":1,"Platform":"macOS","Operation":"%s","Status":"%s","ExitCode":%s,' \
            "$(if [[ "$APPLY" == true ]]; then print -n Apply; else print -n Preview; fi)" "$(json_escape "$STATUS")" "$EXIT_CODE"
        printf '"HostName":"%s","UserName":"%s","TailscaleIPv4":"%s","SshPort":%s,"PythonPath":"%s","Results":[' \
            "$(json_escape "$host_name")" "$(json_escape "$user_name")" "$(json_escape "$TAILSCALE_IP")" "$SSH_PORT" "$(json_escape "$PYTHON_PATH")"
        local separator='' record name result_status code changed message
        for record in "${RESULTS[@]}"; do
            IFS=$'\x1f' read -r name result_status code changed message <<<"$record"
            printf '%s{"Name":"%s","Status":"%s","ExitCode":%s,"Changed":%s,"Message":"%s"}' \
                "$separator" "$(json_escape "$name")" "$(json_escape "$result_status")" "$code" "$changed" "$(json_escape "$message")"
            separator=','
        done
        printf '],"ManualSteps":['
        separator=''
        local location command verify reason
        for record in "${MANUAL_STEPS[@]}"; do
            IFS=$'\x1f' read -r name location command verify reason <<<"$record"
            printf '%s{"Name":"%s","Location":"%s","Command":"%s","VerifyCommand":"%s","Reason":"%s"}' \
                "$separator" "$(json_escape "$name")" "$(json_escape "$location")" "$(json_escape "$command")" \
                "$(json_escape "$verify")" "$(json_escape "$reason")"
            separator=','
        done
        printf '],"NextCommands":['
        if [[ -n "$TAILSCALE_IP" ]]; then
            printf '"ssh %s@%s"' "$(json_escape "$user_name")" "$(json_escape "$TAILSCALE_IP")"
        fi
        printf '],"RerunCommand":"%s"}\n' "$(json_escape "$rerun_command")"
        return 0
    fi

    printf '[%s] platform=macOS operation=%s exit=%s host=%s tailscale=%s\n' "$STATUS" \
        "$(if [[ "$APPLY" == true ]]; then print -n Apply; else print -n Preview; fi)" "$EXIT_CODE" "$host_name" "$TAILSCALE_IP"
    local record name result_status code changed message
    for record in "${RESULTS[@]}"; do
        IFS=$'\x1f' read -r name result_status code changed message <<<"$record"
        printf -- '- %s: %s - %s\n' "$name" "$result_status" "$message"
    done
    if (( ${#MANUAL_STEPS[@]} > 0 )); then
        printf 'Manual steps:\n'
        local location command verify reason
        for record in "${MANUAL_STEPS[@]}"; do
            IFS=$'\x1f' read -r name location command verify reason <<<"$record"
            printf -- '- %s @ %s\n  操作: %s\n  验证: %s\n  原因: %s\n' "$name" "$location" "$command" "$verify" "$reason"
        done
    fi
    [[ -n "$TAILSCALE_IP" ]] && printf 'Next: ssh %s@%s\n' "$user_name" "$TAILSCALE_IP"
    printf 'Rerun: %s\n' "$rerun_command"
}

while (( $# > 0 )); do
    case "$1" in
        --apply) APPLY=true; shift ;;
        --output-format)
            (( $# >= 2 )) || { print -u2 -- '--output-format 需要值'; exit 2; }
            OUTPUT_FORMAT="${2:l}"
            shift 2
            ;;
        --ssh-port)
            (( $# >= 2 )) || { print -u2 -- '--ssh-port 需要值'; exit 2; }
            SSH_PORT="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) print -u2 -- "未知参数: $1"; exit 2 ;;
    esac
done

[[ "$OUTPUT_FORMAT" == 'text' || "$OUTPUT_FORMAT" == 'json' ]] || { print -u2 -- "不支持的输出格式: $OUTPUT_FORMAT"; exit 2; }
[[ "$SSH_PORT" == <-> ]] && (( SSH_PORT >= 1 && SSH_PORT <= 65535 )) || { print -u2 -- 'SSH 端口必须为 1..65535'; exit 2; }

host_name="$(hostname 2>/dev/null || print unknown)"
user_name="$(id -un 2>/dev/null || print unknown)"
rerun_command="zsh macos/bootstrap/prepare-ansible-host.zsh --apply --ssh-port $SSH_PORT --output-format json"
uname_system="${POWERSHELL_SCRIPTS_UNAME_S:-$(uname -s)}"
if [[ "$uname_system" != 'Darwin' ]]; then
    add_result 'Platform' 'Blocked' 10 false '该入口只能在 macOS 目标机运行'
    EXIT_CODE=10
    STATUS='Blocked'
    write_document "$host_name" "$user_name" "$rerun_command"
    exit "$EXIT_CODE"
fi

if ! prepare_sudo; then
    add_result 'Privilege' 'Blocked' 10 false '当前用户无法获得 sudo 权限'
    add_manual_step 'GrantAdministrator' '系统设置 > 用户与群组' \
        '使用现有管理员账号将当前用户设为管理员，或改用管理员账号运行脚本' \
        'sudo -v' 'Homebrew、Remote Login 和防火墙配置需要管理员权限'
    EXIT_CODE=10
else
    add_result 'Privilege' "$(if [[ "$APPLY" == true ]]; then print -n AlreadyPresent; else print -n Preview; fi)" 0 false 'sudo 提权路径可用'
fi

if (( EXIT_CODE == 0 )); then
    ensure_homebrew || { add_result 'Homebrew' 'Failed' 1 false 'Homebrew 安装失败'; EXIT_CODE=1; }
fi
if (( EXIT_CODE == 0 )); then
    ensure_python || { add_result 'Python3' 'Failed' 1 false 'Python 3 安装失败'; EXIT_CODE=1; }
fi
if (( EXIT_CODE == 0 )); then
    ensure_tailscale || { add_result 'TailscaleInstall' 'Failed' 1 false 'Tailscale 安装失败'; EXIT_CODE=1; }
fi
if (( EXIT_CODE == 0 )); then
    ensure_remote_login
    remote_exit=$?
    (( remote_exit == 10 )) && EXIT_CODE=10
    (( remote_exit == 1 )) && { add_result 'RemoteLogin' 'Failed' 1 false 'Remote Login 配置失败'; EXIT_CODE=1; }
fi
if (( EXIT_CODE == 0 )); then
    ensure_firewall_access || { add_result 'FirewallRule' 'Failed' 1 false 'Application Firewall SSH 例外配置失败'; EXIT_CODE=1; }
fi

if detect_tailscale_ip; then
    add_result 'TailscaleLogin' 'AlreadyPresent' 0 false "Tailscale IPv4: $TAILSCALE_IP"
else
    add_manual_step 'ApproveTailscaleSystemExtension' '系统设置 > 通用 > 登录项与扩展 > 网络扩展' \
        '允许 Tailscale 网络扩展；若系统提示需要批准，请按提示完成并重新打开 Tailscale' \
        '打开 Tailscale App，确认状态不是 Needs approval' 'macOS 网络扩展批准必须由用户在系统设置中完成'
    add_manual_step 'LoginTailscale' '菜单栏 Tailscale 图标或 Tailscale App' \
        '选择 Log in，在浏览器完成账号授权；授权后返回 App 等待 Connected' \
        '/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4' '账号授权和设备批准需要用户交互'
    if [[ "$APPLY" == true && "$EXIT_CODE" -eq 0 ]]; then
        add_result 'TailscaleLogin' 'Blocked' 10 false 'Tailscale 已安装，但尚未完成系统扩展批准或 tailnet 登录'
        EXIT_CODE=10
    else
        add_result 'TailscaleLogin' 'Preview' 0 false '安装后批准网络扩展并登录 Tailscale'
    fi
fi

if [[ "$APPLY" == true && "$EXIT_CODE" -eq 0 ]]; then
    if remote_login_enabled && [[ -n "$PYTHON_PATH" ]] && [[ -n "$TAILSCALE_IP" ]]; then
        add_result 'Verification' 'Succeeded' 0 false "Remote Login、Python 和 Tailscale 已就绪: ssh $user_name@$TAILSCALE_IP"
    else
        add_result 'Verification' 'Failed' 1 false 'Remote Login、Python 或 Tailscale 验证失败'
        EXIT_CODE=1
    fi
fi

if [[ "$APPLY" != true ]]; then
    STATUS='Preview'
    EXIT_CODE=0
elif (( EXIT_CODE == 1 )); then
    STATUS='Failed'
elif (( EXIT_CODE == 10 )); then
    STATUS='Blocked'
else
    STATUS='Succeeded'
fi

write_document "$host_name" "$user_name" "$rerun_command"
exit "$EXIT_CODE"
