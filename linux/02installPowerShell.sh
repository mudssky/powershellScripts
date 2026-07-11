#!/usr/bin/env bash

set -euo pipefail

NETWORK_MODE='Direct'
PACKAGE_PATH=''
UNATTENDED=false
NON_INTERACTIVE=false
DRY_RUN=false

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=linux/lib/install-common.sh
source "$SCRIPT_DIR/lib/install-common.sh"

# 功能：输出 PowerShell 安装步骤帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: 02installPowerShell.sh [options]

Options:
  --network-mode Direct|China|Auto  Stage 0 网络模式，默认 Direct
  --package <path>                  显式本地 PowerShell deb 或 linux-x64.tar.gz
  --unattended                     无人值守模式
  --non-interactive                严格非交互模式
  --dry-run                        只显示计划
  -h, --help                       显示帮助
EOF
}

# 功能：判断当前 pwsh 是否满足主版本 7。
# 参数：无。
# 返回：0 满足，1 不满足或不可用。
test_pwsh7() {
    if [ "${POWERSHELL_SCRIPTS_FORCE_MISSING_PWSH:-}" = '1' ] || ! command -v pwsh >/dev/null 2>&1; then
        return 1
    fi
    local major
    major="$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>/dev/null)" || return 1
    case "$major" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$major" -ge 7 ]
}

# 功能：通过 dpkg 安装一个 PowerShell deb，并修复缺失依赖。
# 参数：$1 deb 文件路径。
# 返回：0 安装成功，1 dpkg/apt 失败。
install_powershell_deb() {
    local package_path="$1"
    if sudo dpkg -i "$package_path"; then
        return 0
    fi
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -f -y
    sudo dpkg -i "$package_path"
}

# 功能：把 PowerShell Linux tarball 原子部署到系统目录。
# 参数：$1 tar.gz 路径，$2 目标目录，默认由调用方传入稳定目录。
# 返回：0 安装成功，非零表示解包或系统写入失败。
install_powershell_tarball() {
    local package_path="$1"
    local install_dir="$2"
    local staging_dir
    staging_dir="$(mktemp -d -t powershellScripts-pwsh-install.XXXXXX)"
    trap 'rm -rf "$staging_dir"' RETURN
    tar -xzf "$package_path" -C "$staging_dir"
    sudo install -d -m 0755 "$install_dir"
    sudo cp -a "$staging_dir/." "$install_dir/"
    sudo chmod 0755 "$install_dir/pwsh"
    sudo ln -sfn "$install_dir/pwsh" /usr/bin/pwsh
    rm -rf "$staging_dir"
    trap - RETURN
}

# 功能：使用官方 hashes.sha256 校验下载的 PowerShell 资产。
# 参数：$1 资产路径，$2 hash 清单路径。
# 返回：0 校验成功，1 未找到资产条目或摘要不一致。
verify_powershell_asset() {
    local package_path="$1"
    local hashes_path="$2"
    local package_name expected actual
    package_name="$(basename -- "$package_path")"
    expected="$(awk -v name="$package_name" '$2 == name || $2 == "*" name { print $1; exit }' "$hashes_path")"
    [ -n "$expected" ] || return 1
    actual="$(sha256sum "$package_path" | awk '{print $1}')"
    [ "$actual" = "$expected" ]
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --network-mode)
            [ "$#" -ge 2 ] || linux_install_fail '--network-mode 需要一个值' 2
            NETWORK_MODE="$2"
            shift 2
            ;;
        --package)
            [ "$#" -ge 2 ] || linux_install_fail '--package 需要一个值' 2
            PACKAGE_PATH="$2"
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            linux_install_fail "未知参数: $1" 2
            ;;
    esac
done

linux_install_value_in "$NETWORK_MODE" Direct China Auto || linux_install_fail "不支持的 network mode: $NETWORK_MODE" 2
[ "$UNATTENDED" != true ] || [ "$NON_INTERACTIVE" != true ] || linux_install_fail '--unattended 与 --non-interactive 不能同时使用' 2
linux_install_detect_platform || linux_install_fail 'PowerShell Linux 步骤只能在 Linux/WSL 中运行' 10
[ "$LI_ARCHITECTURE" = 'amd64' ] || linux_install_fail "首期不支持架构: $LI_ARCHITECTURE" 10
linux_install_value_in "$LI_DISTRIBUTION_FAMILY" debian arch || linux_install_fail "不支持发行版: $LI_DISTRIBUTION_ID" 10

if [ -n "$PACKAGE_PATH" ] && [ ! -f "$PACKAGE_PATH" ]; then
    linux_install_fail "PowerShell 安装包不存在: $PACKAGE_PATH" 2
fi
if test_pwsh7; then
    printf 'PowerShell 7 已就绪: %s\n' "$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
    exit 0
fi
if [ -z "$PACKAGE_PATH" ] && [ "$NETWORK_MODE" != 'Direct' ]; then
    linux_install_fail 'China/Auto 缺少 Linux PowerShell Stage 0 下载 adapter；请提供本地安装包或预装 PowerShell 7' 10
fi

linux_install_prepare_sudo "$UNATTENDED" "$NON_INTERACTIVE" "$DRY_RUN" ||
    linux_install_fail '当前交互模式无法获得 sudo 权限' 10

if [ "$DRY_RUN" = true ]; then
    if [ -n "$PACKAGE_PATH" ]; then
        if [ "$LI_DISTRIBUTION_FAMILY" = 'arch' ]; then
            linux_install_print_command sudo install '<powershell-files>' /opt/microsoft/powershell/7
            linux_install_print_command sudo ln -sfn /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh
        else
            linux_install_print_command sudo dpkg -i "$PACKAGE_PATH"
        fi
    else
        if [ "$LI_DISTRIBUTION_FAMILY" = 'arch' ]; then
            printf '[DRY] 从 PowerShell GitHub 最新稳定版下载 linux-x64 tarball 并校验 SHA256\n'
            linux_install_print_command sudo install '<powershell-files>' /opt/microsoft/powershell/7
        else
            printf '[DRY] 从 PowerShell GitHub 最新稳定版下载 amd64 deb 到临时目录\n'
            linux_install_print_command sudo dpkg -i '<temporary-powershell.deb>'
        fi
    fi
    exit 0
fi

if [ -z "$PACKAGE_PATH" ]; then
    command -v curl >/dev/null 2>&1 || linux_install_fail '缺少 curl，无法下载 PowerShell' 10
    work_dir="$(mktemp -d -t powershellScripts-pwsh.XXXXXX)"
    trap 'rm -rf "$work_dir"' EXIT
    latest_version="$(curl -fsSL 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' |
        sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$latest_version" ] || linux_install_fail '无法解析 PowerShell 最新稳定版本' 1
    if [ "$LI_DISTRIBUTION_FAMILY" = 'arch' ]; then
        package_name="powershell-${latest_version#v}-linux-x64.tar.gz"
    else
        package_name="powershell_${latest_version#v}-1.deb_amd64.deb"
    fi
    PACKAGE_PATH="$work_dir/$package_name"
    curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/$latest_version/$package_name" -o "$PACKAGE_PATH"
    if [ "$LI_DISTRIBUTION_FAMILY" = 'arch' ]; then
        hashes_path="$work_dir/hashes.sha256"
        curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/$latest_version/hashes.sha256" -o "$hashes_path"
        verify_powershell_asset "$PACKAGE_PATH" "$hashes_path" || linux_install_fail 'PowerShell 官方 SHA256 校验失败' 1
    fi
fi

if [ "$LI_DISTRIBUTION_FAMILY" = 'arch' ]; then
    case "$PACKAGE_PATH" in
        *.tar.gz) ;;
        *) linux_install_fail 'Arch PowerShell 本地包必须是 .tar.gz' 2 ;;
    esac
    install_powershell_tarball "$PACKAGE_PATH" '/opt/microsoft/powershell/7' || linux_install_fail 'PowerShell tarball 安装失败'
else
    case "$PACKAGE_PATH" in
        *.deb) ;;
        *) linux_install_fail 'Debian PowerShell 本地包必须是 .deb' 2 ;;
    esac
    install_powershell_deb "$PACKAGE_PATH" || linux_install_fail 'PowerShell deb 安装失败'
fi
hash -r
test_pwsh7 || linux_install_fail 'PowerShell 安装后版本验证失败'
printf 'PowerShell 安装完成: %s\n' "$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
