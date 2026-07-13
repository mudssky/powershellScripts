#!/usr/bin/env bash
# WSL 客体 SSH 管理入口。包、sshd 配置和 authorized_keys 只在本脚本中维护。
set -euo pipefail

OPERATION="plan"
TARGET_USER=""
SSH_PORT="22"
AUTHORIZED_KEY_BASE64=""
OUTPUT_FORMAT="json"
MANAGED_CONFIG="/etc/ssh/sshd_config.d/90-powershellscripts-wsl-ssh.conf"
MANAGED_KEY_MARKER="powershellScripts-wsl-ssh"

usage() {
    cat <<'EOF'
Usage: prepare-ssh-access.sh --operation plan|apply|verify|rollback \
  --user <linux-user> [--port <1..65535>] \
  [--authorized-key-base64 <base64>] [--output-format json|text]
EOF
}

json_escape() {
    local value=${1-}
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

emit_document() {
    local status=$1
    local exit_code=$2
    local changed=$3
    local message=$4
    local package_installed=$5
    local service_enabled=$6
    local service_active=$7
    local listener_ready=$8
    local key_fingerprint=${9-}

    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        printf '[%s] operation=%s changed=%s user=%s port=%s message=%s\n' \
            "$status" "$OPERATION" "$changed" "$TARGET_USER" "$SSH_PORT" "$message"
        return
    fi
    printf '{"schemaVersion":1,"platform":"wsl","operation":"%s","status":"%s","exitCode":%s,"changed":%s,"user":"%s","port":%s,"packageInstalled":%s,"serviceEnabled":%s,"serviceActive":%s,"listenerReady":%s,"keyFingerprint":"%s","message":"%s"}\n' \
        "$(json_escape "$OPERATION")" "$(json_escape "$status")" "$exit_code" "$changed" \
        "$(json_escape "$TARGET_USER")" "$SSH_PORT" "$package_installed" "$service_enabled" \
        "$service_active" "$listener_ready" "$(json_escape "$key_fingerprint")" "$(json_escape "$message")"
}

fail_invalid() {
    emit_document "Invalid" 2 false "$1" false false false false ""
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --operation)
            [[ $# -ge 2 ]] || fail_invalid "--operation requires a value"
            OPERATION=$2
            shift 2
            ;;
        --user)
            [[ $# -ge 2 ]] || fail_invalid "--user requires a value"
            TARGET_USER=$2
            shift 2
            ;;
        --port)
            [[ $# -ge 2 ]] || fail_invalid "--port requires a value"
            SSH_PORT=$2
            shift 2
            ;;
        --authorized-key-base64)
            [[ $# -ge 2 ]] || fail_invalid "--authorized-key-base64 requires a value"
            AUTHORIZED_KEY_BASE64=$2
            shift 2
            ;;
        --output-format)
            [[ $# -ge 2 ]] || fail_invalid "--output-format requires a value"
            OUTPUT_FORMAT=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail_invalid "unknown argument: $1"
            ;;
    esac
done

[[ "$OPERATION" =~ ^(plan|apply|verify|rollback)$ ]] || fail_invalid "invalid operation"
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || fail_invalid "invalid Linux user"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || fail_invalid "invalid SSH port"
((SSH_PORT >= 1 && SSH_PORT <= 65535)) || fail_invalid "invalid SSH port"
[[ "$OUTPUT_FORMAT" =~ ^(json|text)$ ]] || fail_invalid "invalid output format"

if [[ "${WSL_SSH_ACCESS_TEST_MODE:-0}" == "1" ]]; then
    emit_document "Preview" 0 true "test fixture plan" false false false false "SHA256:test"
    exit 0
fi

if ! grep -Eiq '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null; then
    emit_document "Blocked" 10 false "current Linux is not WSL" false false false false ""
    exit 10
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" && "${ID:-}" != "debian" ]]; then
    emit_document "Blocked" 10 false "only Ubuntu or Debian WSL is supported" false false false false ""
    exit 10
fi
if ! id "$TARGET_USER" >/dev/null 2>&1; then
    emit_document "Blocked" 10 false "target Linux user does not exist" false false false false ""
    exit 10
fi

AUTHORIZED_KEY=""
KEY_FINGERPRINT=""
if [[ -n "$AUTHORIZED_KEY_BASE64" ]]; then
    AUTHORIZED_KEY=$(printf '%s' "$AUTHORIZED_KEY_BASE64" | base64 --decode 2>/dev/null || true)
    if [[ ! "$AUTHORIZED_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^[:space:]]+)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
        fail_invalid "invalid SSH public key"
    fi
    KEY_FINGERPRINT=$(printf '%s\n' "$AUTHORIZED_KEY" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
    [[ -n "$KEY_FINGERPRINT" ]] || fail_invalid "cannot calculate SSH key fingerprint"
fi

HOME_DIR=$(getent passwd "$TARGET_USER" | cut -d: -f6)
AUTHORIZED_KEYS="$HOME_DIR/.ssh/authorized_keys"
MANAGED_CONFIG_CONTENT=$(cat <<EOF
# Managed by powershellScripts WSL SSH access.
Port $SSH_PORT
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers $TARGET_USER
EOF
)

PACKAGE_INSTALLED=false
SERVICE_ENABLED=false
SERVICE_ACTIVE=false
LISTENER_READY=false
CONFIG_MATCHES=false
KEY_PRESENT=false

if dpkg-query -W -f='${Status}' openssh-server 2>/dev/null | grep -q 'install ok installed'; then
    PACKAGE_INSTALLED=true
fi
if [[ -f "$MANAGED_CONFIG" ]] && [[ "$(cat "$MANAGED_CONFIG")" == "$MANAGED_CONFIG_CONTENT" ]]; then
    CONFIG_MATCHES=true
fi
if [[ -n "$KEY_FINGERPRINT" && -f "$AUTHORIZED_KEYS" ]] && grep -Fq "$MANAGED_KEY_MARKER:$KEY_FINGERPRINT" "$AUTHORIZED_KEYS"; then
    KEY_PRESENT=true
fi
if systemctl is-enabled ssh >/dev/null 2>&1; then
    SERVICE_ENABLED=true
fi
if systemctl is-active ssh >/dev/null 2>&1; then
    SERVICE_ACTIVE=true
fi
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$SSH_PORT$"; then
    LISTENER_READY=true
fi

case "$OPERATION" in
    plan)
        CHANGED=false
        if [[ "$PACKAGE_INSTALLED" != true || "$CONFIG_MATCHES" != true || "$KEY_PRESENT" != true || "$SERVICE_ENABLED" != true || "$SERVICE_ACTIVE" != true || "$LISTENER_READY" != true ]]; then
            CHANGED=true
        fi
        emit_document "Preview" 0 "$CHANGED" "WSL SSH plan generated" "$PACKAGE_INSTALLED" "$SERVICE_ENABLED" "$SERVICE_ACTIVE" "$LISTENER_READY" "$KEY_FINGERPRINT"
        ;;
    verify)
        if [[ "$PACKAGE_INSTALLED" == true && "$CONFIG_MATCHES" == true && "$KEY_PRESENT" == true && "$SERVICE_ENABLED" == true && "$SERVICE_ACTIVE" == true && "$LISTENER_READY" == true ]]; then
            emit_document "Succeeded" 0 false "WSL SSH is ready" true true true true "$KEY_FINGERPRINT"
        else
            emit_document "Failed" 1 false "WSL SSH verification failed" "$PACKAGE_INSTALLED" "$SERVICE_ENABLED" "$SERVICE_ACTIVE" "$LISTENER_READY" "$KEY_FINGERPRINT"
            exit 1
        fi
        ;;
    apply)
        [[ $EUID -eq 0 ]] || {
            emit_document "Blocked" 10 false "apply requires root" "$PACKAGE_INSTALLED" "$SERVICE_ENABLED" "$SERVICE_ACTIVE" "$LISTENER_READY" "$KEY_FINGERPRINT"
            exit 10
        }
        [[ -n "$AUTHORIZED_KEY" ]] || fail_invalid "apply requires an authorized key"
        read -r KEY_TYPE KEY_BODY _ <<<"$AUTHORIZED_KEY"
        CHANGED=false
        if [[ "$PACKAGE_INSTALLED" != true ]]; then
            if ! apt-get -o DPkg::Lock::Timeout=300 update >&2; then
                emit_document "Failed" 1 false "apt update failed" false "$SERVICE_ENABLED" "$SERVICE_ACTIVE" "$LISTENER_READY" "$KEY_FINGERPRINT"
                exit 1
            fi
            if ! DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y openssh-server >&2; then
                emit_document "Failed" 1 false "openssh-server installation failed" false "$SERVICE_ENABLED" "$SERVICE_ACTIVE" "$LISTENER_READY" "$KEY_FINGERPRINT"
                exit 1
            fi
            CHANGED=true
        fi
        install -d -m 0755 "$(dirname "$MANAGED_CONFIG")"
        if [[ "$CONFIG_MATCHES" != true ]]; then
            TEMP_CONFIG=$(mktemp)
            printf '%s\n' "$MANAGED_CONFIG_CONTENT" >"$TEMP_CONFIG"
            install -m 0644 "$TEMP_CONFIG" "$MANAGED_CONFIG"
            rm -f "$TEMP_CONFIG"
            CHANGED=true
        fi
        install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_USER" "$HOME_DIR/.ssh"
        TEMP_KEYS=$(mktemp)
        if [[ -f "$AUTHORIZED_KEYS" ]]; then
            grep -Fv "$MANAGED_KEY_MARKER:" "$AUTHORIZED_KEYS" >"$TEMP_KEYS" || true
        fi
        printf '%s %s %s:%s\n' "$KEY_TYPE" "$KEY_BODY" "$MANAGED_KEY_MARKER" "$KEY_FINGERPRINT" >>"$TEMP_KEYS"
        if [[ ! -f "$AUTHORIZED_KEYS" ]] || ! cmp -s "$TEMP_KEYS" "$AUTHORIZED_KEYS"; then
            install -m 0600 -o "$TARGET_USER" -g "$TARGET_USER" "$TEMP_KEYS" "$AUTHORIZED_KEYS"
            CHANGED=true
        fi
        rm -f "$TEMP_KEYS"
        sshd -t
        systemctl enable ssh >/dev/null
        if [[ "$CHANGED" == true ]]; then
            systemctl restart ssh
        else
            systemctl start ssh
        fi
        SERVICE_ENABLED=$(systemctl is-enabled ssh >/dev/null 2>&1 && echo true || echo false)
        SERVICE_ACTIVE=$(systemctl is-active ssh >/dev/null 2>&1 && echo true || echo false)
        LISTENER_READY=$(ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$SSH_PORT$" && echo true || echo false)
        if [[ "$SERVICE_ENABLED" != true || "$SERVICE_ACTIVE" != true || "$LISTENER_READY" != true ]]; then
            emit_document "Failed" 1 "$CHANGED" "WSL SSH apply verification failed" true "$SERVICE_ENABLED" "$SERVICE_ACTIVE" "$LISTENER_READY" "$KEY_FINGERPRINT"
            exit 1
        fi
        emit_document "Succeeded" 0 "$CHANGED" "WSL SSH applied" true true true true "$KEY_FINGERPRINT"
        ;;
    rollback)
        [[ $EUID -eq 0 ]] || {
            emit_document "Blocked" 10 false "rollback requires root" "$PACKAGE_INSTALLED" "$SERVICE_ENABLED" "$SERVICE_ACTIVE" "$LISTENER_READY" "$KEY_FINGERPRINT"
            exit 10
        }
        CHANGED=false
        if [[ -f "$MANAGED_CONFIG" ]]; then
            rm -f "$MANAGED_CONFIG"
            CHANGED=true
        fi
        if [[ -f "$AUTHORIZED_KEYS" ]] && grep -Fq "$MANAGED_KEY_MARKER:" "$AUTHORIZED_KEYS"; then
            TEMP_KEYS=$(mktemp)
            grep -Fv "$MANAGED_KEY_MARKER:" "$AUTHORIZED_KEYS" >"$TEMP_KEYS" || true
            install -m 0600 -o "$TARGET_USER" -g "$TARGET_USER" "$TEMP_KEYS" "$AUTHORIZED_KEYS"
            rm -f "$TEMP_KEYS"
            CHANGED=true
        fi
        if [[ "$PACKAGE_INSTALLED" == true ]]; then
            sshd -t
            systemctl restart ssh || true
        fi
        emit_document "Succeeded" 0 "$CHANGED" "managed WSL SSH access rolled back" "$PACKAGE_INSTALLED" "$SERVICE_ENABLED" "$SERVICE_ACTIVE" "$LISTENER_READY" "$KEY_FINGERPRINT"
        ;;
esac
