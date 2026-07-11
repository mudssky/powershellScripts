#!/usr/bin/env bash

# Linux 安装叶子共享平台探测和参数校验；本文件被 source，不主动执行命令。

# 功能：输出 Linux 安装错误并以指定退出码结束当前脚本。
# 参数：$1 错误消息，$2 可选退出码，默认 1。
# 返回：不返回。
linux_install_fail() {
    printf '%s\n' "$1" >&2
    exit "${2:-1}"
}

# 功能：校验值是否属于允许集合。
# 参数：$1 待校验值，$2 起为允许值。
# 返回：0 属于集合，1 不属于集合。
linux_install_value_in() {
    local value="$1"
    shift
    local candidate
    for candidate in "$@"; do
        if [ "$value" = "$candidate" ]; then
            return 0
        fi
    done
    return 1
}

# 功能：读取 os-release 中指定键的原始值，不执行文件内容。
# 参数：$1 文件路径，$2 键名。
# 返回：0 找到并输出去除外层引号的值，1 未找到。
linux_install_read_os_release() {
    local file_path="$1"
    local key="$2"
    local line value

    [ -r "$file_path" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "$key"=*)
                value="${line#*=}"
                case "$value" in
                    \"*\") value="${value#\"}"; value="${value%\"}" ;;
                    \'*\') value="${value#\'}"; value="${value%\'}" ;;
                esac
                printf '%s\n' "$value"
                return 0
                ;;
        esac
    done < "$file_path"
    return 1
}

# 功能：规范化 uname/Runtime 风格的 CPU 架构。
# 参数：$1 原始架构名称。
# 返回：0 并输出 amd64、arm64 或 unknown。
linux_install_normalize_architecture() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        x86_64|x64|amd64) printf 'amd64\n' ;;
        aarch64|arm64) printf 'arm64\n' ;;
        *) printf 'unknown\n' ;;
    esac
}

# 功能：探测 Linux 发行版、WSL 和架构并写入 LI_* 全局变量。
# 参数：无；测试可通过 POWERSHELL_SCRIPTS_*_PATH/ARCHITECTURE 覆盖输入。
# 返回：0 完成探测；10 当前系统不是 Linux。
linux_install_detect_platform() {
    local uname_system os_release_path proc_version_path raw_arch id_like proc_version
    uname_system="${POWERSHELL_SCRIPTS_UNAME_S:-$(uname -s)}"
    if [ "$uname_system" != 'Linux' ]; then
        return 10
    fi

    os_release_path="${POWERSHELL_SCRIPTS_OS_RELEASE_PATH:-/etc/os-release}"
    proc_version_path="${POWERSHELL_SCRIPTS_PROC_VERSION_PATH:-/proc/version}"
    LI_DISTRIBUTION_ID="$(linux_install_read_os_release "$os_release_path" ID 2>/dev/null || true)"
    LI_DISTRIBUTION_ID="$(printf '%s' "${LI_DISTRIBUTION_ID:-unknown}" | tr '[:upper:]' '[:lower:]')"
    id_like="$(linux_install_read_os_release "$os_release_path" ID_LIKE 2>/dev/null || true)"

    case "$LI_DISTRIBUTION_ID $id_like" in
        *ubuntu*|*debian*) LI_DISTRIBUTION_FAMILY='debian' ;;
        *arch*) LI_DISTRIBUTION_FAMILY='arch' ;;
        *) LI_DISTRIBUTION_FAMILY='unknown' ;;
    esac

    raw_arch="${POWERSHELL_SCRIPTS_ARCHITECTURE:-$(uname -m)}"
    LI_ARCHITECTURE="$(linux_install_normalize_architecture "$raw_arch")"
    proc_version=''
    if [ -r "$proc_version_path" ]; then
        proc_version="$(cat "$proc_version_path" 2>/dev/null || true)"
    fi
    LI_IS_WSL=false
    if [ -n "${WSL_INTEROP:-}" ] || [ -n "${WSL_DISTRO_NAME:-}" ] ||
        printf '%s' "$proc_version" | grep -Eiq 'microsoft|wsl'; then
        LI_IS_WSL=true
    fi
    export LI_DISTRIBUTION_ID LI_DISTRIBUTION_FAMILY LI_ARCHITECTURE LI_IS_WSL
    return 0
}

# 功能：为无人值守模式准备 sudo 凭据。
# 参数：$1 unattended 布尔值，$2 non-interactive 布尔值，$3 dry-run 布尔值。
# 返回：0 已满足或无需检查，10 无法获得 sudo。
linux_install_prepare_sudo() {
    local unattended="$1"
    local non_interactive="$2"
    local dry_run="$3"

    [ "$dry_run" = true ] && return 0
    if [ "$non_interactive" = true ]; then
        sudo -n true >/dev/null 2>&1 || return 10
    elif [ "$unattended" = true ]; then
        sudo -v || return 10
    fi
}

# 功能：以稳定展示格式输出 dry-run 命令，不执行字符串拼接命令。
# 参数：完整命令及参数数组。
# 返回：0。
linux_install_print_command() {
    printf '[DRY]'
    printf ' %q' "$@"
    printf '\n'
}
