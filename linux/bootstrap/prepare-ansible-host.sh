#!/usr/bin/env bash

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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=linux/lib/install-common.sh
source "$SCRIPT_DIR/../lib/install-common.sh"

# 功能：输出脚本帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: prepare-ansible-host.sh [options]

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
    printf '%s' "$value"
}

# 功能：从可选测试覆盖或真实命令判断布尔状态。
# 参数：$1 环境变量名称，$2 探测命令。
# 返回：0 为 true，1 为 false。
state_or_command() {
    local variable_name="$1"
    shift
    local override="${!variable_name:-}"
    if [ "$override" = '1' ]; then
        return 0
    fi
    if [ "$override" = '0' ]; then
        return 1
    fi
    "$@"
}

# 功能：返回 root 或 sudo 命令前缀。
# 参数：无。
# 返回：0 并通过 SUDO_PREFIX 数组返回；10 无提权路径。
prepare_privilege() {
    SUDO_PREFIX=()
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        return 10
    fi
    if [ "$APPLY" = true ]; then
        sudo -v || return 10
    fi
    SUDO_PREFIX=(sudo)
    return 0
}

# 功能：检查并安装 Debian 或 Arch 前置包。
# 参数：$1 发行版 family。
# 返回：0 成功，1 安装失败。
install_platform_packages() {
    local family="$1"
    local packages=()
    command -v sudo >/dev/null 2>&1 || packages+=(sudo)
    command -v python3 >/dev/null 2>&1 || packages+=(python3)
    command -v sshd >/dev/null 2>&1 || {
        if [ "$family" = 'debian' ]; then packages+=(openssh-server); else packages+=(openssh); fi
    }
    command -v curl >/dev/null 2>&1 || packages+=(curl)

    if [ "${#packages[@]}" -eq 0 ]; then
        add_result 'PlatformPackages' 'AlreadyPresent' 0 false 'sudo、Python 3、OpenSSH 和 curl 已安装'
        return 0
    fi
    if [ "$APPLY" != true ]; then
        if [ "$family" = 'debian' ]; then
            add_result 'PlatformPackages' 'Preview' 0 false "sudo apt-get update && sudo apt-get install -y ${packages[*]}"
        else
            add_result 'PlatformPackages' 'Preview' 0 false "sudo pacman -Syu --needed --noconfirm ${packages[*]}"
        fi
        return 0
    fi

    if [ "$family" = 'debian' ]; then
        "${SUDO_PREFIX[@]}" apt-get update || return 1
        "${SUDO_PREFIX[@]}" apt-get install -y "${packages[@]}" || return 1
    else
        "${SUDO_PREFIX[@]}" pacman -Syu --needed --noconfirm "${packages[@]}" || return 1
    fi
    add_result 'PlatformPackages' 'Succeeded' 0 true "已安装: ${packages[*]}"
    return 0
}

# 功能：检查并安装 Tailscale。
# 参数：无。
# 返回：0 已安装或安装成功，1 安装失败。
ensure_tailscale_installed() {
    if state_or_command POWERSHELL_SCRIPTS_ANSIBLE_PREP_TAILSCALE_INSTALLED command -v tailscale >/dev/null 2>&1; then
        add_result 'TailscaleInstall' 'AlreadyPresent' 0 false 'Tailscale CLI 已安装'
        return 0
    fi
    if [ "$APPLY" != true ]; then
        add_result 'TailscaleInstall' 'Preview' 0 false 'curl -fsSL https://tailscale.com/install.sh | sh'
        return 0
    fi
    command -v curl >/dev/null 2>&1 || return 1
    if ! curl -fsSL https://tailscale.com/install.sh | sh; then
        return 1
    fi
    add_result 'TailscaleInstall' 'Succeeded' 0 true '已使用 Tailscale 官方安装脚本完成安装'
    return 0
}

# 功能：启用并启动 SSH 与 tailscaled 服务。
# 参数：$1 SSH service 名称。
# 返回：0 成功，1 服务管理失败，10 无 systemd。
ensure_services() {
    local ssh_service="$1"
    if [ "${POWERSHELL_SCRIPTS_ANSIBLE_PREP_SYSTEMD:-}" != '1' ] && ! command -v systemctl >/dev/null 2>&1; then
        add_result 'ServiceManager' 'Blocked' 10 false '未发现 systemd，无法可靠启用 SSH 与 tailscaled'
        add_manual_step 'EnableServices' '目标机 root shell' \
            "使用当前发行版 service manager 启用并启动 $ssh_service 与 tailscaled" \
            "ss -lnt | grep ':$SSH_PORT ' && tailscale ip -4" \
            '当前脚本只为仓库支持范围内的 systemd 主机自动管理服务'
        return 10
    fi

    if [ "$APPLY" != true ]; then
        add_result 'SshdService' 'Preview' 0 false "sudo systemctl enable --now $ssh_service"
        add_result 'TailscaledService' 'Preview' 0 false 'sudo systemctl enable --now tailscaled'
        return 0
    fi
    "${SUDO_PREFIX[@]}" systemctl enable --now "$ssh_service" || return 1
    "${SUDO_PREFIX[@]}" systemctl enable --now tailscaled || return 1
    add_result 'SshdService' 'Succeeded' 0 true "$ssh_service 已启用并启动"
    add_result 'TailscaledService' 'Succeeded' 0 true 'tailscaled 已启用并启动'
    return 0
}

# 功能：发现唯一 Tailscale IPv4。
# 参数：无。
# 返回：0 并设置 TAILSCALE_IP，1 未连接或地址无效。
detect_tailscale_ip() {
    local candidate="${POWERSHELL_SCRIPTS_ANSIBLE_PREP_TAILSCALE_IP:-}"
    if [ -z "$candidate" ] && command -v tailscale >/dev/null 2>&1; then
        candidate="$(tailscale ip -4 2>/dev/null | sed -n '1p')"
    fi
    case "$candidate" in
        100.*)
            local second_octet="${candidate#100.}"
            second_octet="${second_octet%%.*}"
            if [ "$second_octet" -ge 64 ] 2>/dev/null && [ "$second_octet" -le 127 ] 2>/dev/null; then
                TAILSCALE_IP="$candidate"
                return 0
            fi
            ;;
    esac
    return 1
}

# 功能：检测活动防火墙并确保 SSH 可从 tailscale0 访问。
# 参数：无。
# 返回：0 已满足或配置成功，1 配置失败。
ensure_firewall_access() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
        if [ "$APPLY" = true ]; then
            "${SUDO_PREFIX[@]}" ufw allow in on tailscale0 to any port "$SSH_PORT" proto tcp || return 1
            add_result 'FirewallRule' 'Succeeded' 0 true "ufw 已允许 tailscale0 TCP $SSH_PORT；未改变全局开关"
        else
            add_result 'FirewallRule' 'Preview' 0 false "sudo ufw allow in on tailscale0 to any port $SSH_PORT proto tcp"
        fi
        return 0
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        local rule="rule family=ipv4 source address=100.64.0.0/10 port port=$SSH_PORT protocol=tcp accept"
        if [ "$APPLY" = true ]; then
            "${SUDO_PREFIX[@]}" firewall-cmd --permanent --add-rich-rule="$rule" || return 1
            "${SUDO_PREFIX[@]}" firewall-cmd --reload || return 1
            add_result 'FirewallRule' 'Succeeded' 0 true "firewalld 已允许 tailnet TCP $SSH_PORT；未改变全局开关"
        else
            add_result 'FirewallRule' 'Preview' 0 false "sudo firewall-cmd --permanent --add-rich-rule='$rule' && sudo firewall-cmd --reload"
        fi
        return 0
    fi
    add_result 'FirewallRule' 'Skipped' 0 false '未检测到活动 ufw/firewalld；不改变防火墙全局状态'
    return 0
}

# 功能：按统一结构输出 Text 或 Json。
# 参数：$1 platform，$2 host，$3 user，$4 rerun command。
# 返回：0。
write_document() {
    local platform="$1" host_name="$2" user_name="$3" rerun_command="$4"
    if [ "$OUTPUT_FORMAT" = 'json' ]; then
        printf '{"SchemaVersion":1,"Platform":"%s","Operation":"%s","Status":"%s","ExitCode":%s,' \
            "$(json_escape "$platform")" "$(if [ "$APPLY" = true ]; then printf Apply; else printf Preview; fi)" \
            "$(json_escape "$STATUS")" "$EXIT_CODE"
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
        if [ "${#MANUAL_STEPS[@]}" -gt 0 ]; then
            for record in "${MANUAL_STEPS[@]}"; do
                IFS=$'\x1f' read -r name location command verify reason <<<"$record"
                printf '%s{"Name":"%s","Location":"%s","Command":"%s","VerifyCommand":"%s","Reason":"%s"}' \
                    "$separator" "$(json_escape "$name")" "$(json_escape "$location")" "$(json_escape "$command")" \
                    "$(json_escape "$verify")" "$(json_escape "$reason")"
                separator=','
            done
        fi
        printf '],"NextCommands":['
        if [ -n "$TAILSCALE_IP" ]; then
            printf '"ssh %s@%s"' "$(json_escape "$user_name")" "$(json_escape "$TAILSCALE_IP")"
        fi
        printf '],"RerunCommand":"%s"}\n' "$(json_escape "$rerun_command")"
        return 0
    fi

    printf '[%s] platform=%s operation=%s exit=%s host=%s tailscale=%s\n' "$STATUS" "$platform" \
        "$(if [ "$APPLY" = true ]; then printf Apply; else printf Preview; fi)" "$EXIT_CODE" "$host_name" "$TAILSCALE_IP"
    local record name result_status code changed message
    for record in "${RESULTS[@]}"; do
        IFS=$'\x1f' read -r name result_status code changed message <<<"$record"
        printf -- '- %s: %s - %s\n' "$name" "$result_status" "$message"
    done
    if [ "${#MANUAL_STEPS[@]}" -gt 0 ]; then
        printf 'Manual steps:\n'
        local location command verify reason
        for record in "${MANUAL_STEPS[@]}"; do
            IFS=$'\x1f' read -r name location command verify reason <<<"$record"
            printf -- '- %s @ %s\n  操作: %s\n  验证: %s\n  原因: %s\n' "$name" "$location" "$command" "$verify" "$reason"
        done
    fi
    [ -n "$TAILSCALE_IP" ] && printf 'Next: ssh %s@%s\n' "$user_name" "$TAILSCALE_IP"
    printf 'Rerun: %s\n' "$rerun_command"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --apply) APPLY=true; shift ;;
        --output-format)
            [ "$#" -ge 2 ] || { printf '%s\n' '--output-format 需要值' >&2; exit 2; }
            OUTPUT_FORMAT="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
            shift 2
            ;;
        --ssh-port)
            [ "$#" -ge 2 ] || { printf '%s\n' '--ssh-port 需要值' >&2; exit 2; }
            SSH_PORT="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
    esac
done

case "$OUTPUT_FORMAT" in text|json) ;; *) printf '不支持的输出格式: %s\n' "$OUTPUT_FORMAT" >&2; exit 2 ;; esac
case "$SSH_PORT" in ''|*[!0-9]*) printf 'SSH 端口必须为数字\n' >&2; exit 2 ;; esac
[ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ] || { printf 'SSH 端口超出范围\n' >&2; exit 2; }

host_name="$(hostname 2>/dev/null || printf unknown)"
user_name="$(id -un 2>/dev/null || printf unknown)"
rerun_command="bash linux/bootstrap/prepare-ansible-host.sh --apply --ssh-port $SSH_PORT --output-format json"

if ! linux_install_detect_platform; then
    add_result 'Platform' 'Blocked' 10 false '该入口只能在 Linux 目标机运行'
    EXIT_CODE=10
    STATUS='Blocked'
    write_document 'Linux' "$host_name" "$user_name" "$rerun_command"
    exit "$EXIT_CODE"
fi
if [ "$LI_IS_WSL" = true ]; then
    add_result 'Platform' 'Blocked' 10 false 'WSL 客体不自动建立独立 SSH 管理面'
    add_manual_step 'ChooseWslManagementPath' 'Windows 宿主机' \
        '优先让 Ansible 管理 Windows 宿主；如确需独立管理 WSL，请先确认 systemd、固定发行版和端口转发策略' \
        'wsl.exe --status && wsl.exe -l -v' \
        'WSL 网络与生命周期由宿主管理，自动启用 sshd 容易产生不稳定入口'
    EXIT_CODE=10
    STATUS='Blocked'
    write_document 'Linux' "$host_name" "$user_name" "$rerun_command"
    exit "$EXIT_CODE"
fi
if [ "$LI_DISTRIBUTION_FAMILY" != 'debian' ] && [ "$LI_DISTRIBUTION_FAMILY" != 'arch' ]; then
    add_result 'Distribution' 'Blocked' 10 false "暂不支持发行版: $LI_DISTRIBUTION_ID"
    add_manual_step 'InstallPrerequisites' '目标机 root shell' \
        "安装 Python 3、sudo、OpenSSH Server 和 Tailscale，启用 sshd/tailscaled，并放行 tailnet TCP $SSH_PORT" \
        "python3 --version && tailscale ip -4 && ss -lnt | grep ':$SSH_PORT '" \
        '仓库当前只维护 Debian/Ubuntu 与 Arch 的可验证包管理 adapter'
    EXIT_CODE=10
    STATUS='Blocked'
    write_document 'Linux' "$host_name" "$user_name" "$rerun_command"
    exit "$EXIT_CODE"
fi

if ! prepare_privilege; then
    add_result 'Privilege' 'Blocked' 10 false '当前用户无 root/sudo 提权路径'
    package_command='apt-get install -y sudo'
    [ "$LI_DISTRIBUTION_FAMILY" = 'arch' ] && package_command='pacman -Syu --needed sudo'
    add_manual_step 'InstallSudo' 'root 控制台或现有 root SSH 会话' "$package_command" \
        "sudo -v && sudo -n true" '普通用户无法自行安装 sudo'
    EXIT_CODE=10
else
    add_result 'Privilege' "$(if [ "$APPLY" = true ]; then printf AlreadyPresent; else printf Preview; fi)" 0 false 'root/sudo 提权路径可用'
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    install_platform_packages "$LI_DISTRIBUTION_FAMILY" || { add_result 'PlatformPackages' 'Failed' 1 false '平台前置包安装失败'; EXIT_CODE=1; }
fi
if [ "$EXIT_CODE" -eq 0 ]; then
    ensure_tailscale_installed || { add_result 'TailscaleInstall' 'Failed' 1 false 'Tailscale 安装失败'; EXIT_CODE=1; }
fi
ssh_service='ssh'
[ "$LI_DISTRIBUTION_FAMILY" = 'arch' ] && ssh_service='sshd'
if [ "$EXIT_CODE" -eq 0 ]; then
    ensure_services "$ssh_service" || {
        service_exit=$?
        [ "$service_exit" -eq 10 ] && EXIT_CODE=10 || { add_result 'Services' 'Failed' 1 false '服务启用失败'; EXIT_CODE=1; }
    }
fi
if [ "$EXIT_CODE" -eq 0 ]; then
    ensure_firewall_access || { add_result 'FirewallRule' 'Failed' 1 false '防火墙 SSH rule 配置失败'; EXIT_CODE=1; }
fi

if command -v python3 >/dev/null 2>&1; then
    PYTHON_PATH="$(command -v python3)"
elif [ -n "${POWERSHELL_SCRIPTS_ANSIBLE_PREP_PYTHON_PATH:-}" ]; then
    PYTHON_PATH="$POWERSHELL_SCRIPTS_ANSIBLE_PREP_PYTHON_PATH"
fi

if detect_tailscale_ip; then
    add_result 'TailscaleLogin' 'AlreadyPresent' 0 false "Tailscale IPv4: $TAILSCALE_IP"
else
    add_manual_step 'LoginTailscale' '目标机交互式终端' 'sudo tailscale up' 'tailscale ip -4' \
        '浏览器账号授权和设备批准需要用户交互'
    if [ "$APPLY" = true ] && [ "$EXIT_CODE" -eq 0 ]; then
        add_result 'TailscaleLogin' 'Blocked' 10 false 'Tailscale 已安装，但尚未登录 tailnet'
        EXIT_CODE=10
    else
        add_result 'TailscaleLogin' 'Preview' 0 false '安装后执行 sudo tailscale up 完成登录'
    fi
fi

if [ "$APPLY" = true ] && [ "$EXIT_CODE" -eq 0 ]; then
    if systemctl is-active --quiet "$ssh_service" && systemctl is-enabled --quiet "$ssh_service" && [ -n "$PYTHON_PATH" ]; then
        add_result 'Verification' 'Succeeded' 0 false "SSH、Python 和 Tailscale 已就绪: ssh $user_name@$TAILSCALE_IP"
    else
        add_result 'Verification' 'Failed' 1 false 'SSH service 或 Python 验证失败'
        EXIT_CODE=1
    fi
fi

if [ "$APPLY" != true ]; then
    STATUS='Preview'
    EXIT_CODE=0
elif [ "$EXIT_CODE" -eq 1 ]; then
    STATUS='Failed'
elif [ "$EXIT_CODE" -eq 10 ]; then
    STATUS='Blocked'
else
    STATUS='Succeeded'
fi

write_document 'Linux' "$host_name" "$user_name" "$rerun_command"
exit "$EXIT_CODE"
