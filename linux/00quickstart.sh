#!/usr/bin/env bash

set -euo pipefail

REPO_URL='https://github.com/mudssky/powershellScripts.git'
REPO_DIR="${POWERSHELL_SCRIPTS_REPO_DIR:-$HOME/powershellScripts}"
PRESET='Core'
NETWORK_MODE='Direct'
POWERSHELL_PACKAGE=''
UNATTENDED=false
NON_INTERACTIVE=false
DRY_RUN=false

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=linux/lib/install-common.sh
source "$SCRIPT_DIR/lib/install-common.sh"

# 功能：输出 Linux Stage 0 使用说明。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: 00quickstart.sh [options]

Options:
  --repo-url <url>                   仓库地址
  --repo-dir <path>                  clone 目录
  --preset Core|Full                 Stage 1 预设，默认 Core
  --network-mode Direct|China|Auto   网络模式，默认 Direct
  --powershell-package <path>        显式本地 PowerShell deb 或 tar.gz
  --unattended                       允许开头一次 sudo 认证
  --non-interactive                  严格零提示，前置不足返回 10
  --dry-run                          只显示 Stage 0 与移交计划
  -h, --help                         显示帮助
EOF
}

# 功能：判断 Debian 系 Stage 0 的最小 apt 前置是否完整。
# 参数：无。
# 返回：0 全部已安装，1 至少缺少一个前置包。
stage0_apt_prerequisites_ready() {
    if [ "${POWERSHELL_SCRIPTS_FORCE_MISSING_APT_PREREQUISITES:-}" = '1' ]; then
        return 1
    fi

    if command -v dpkg-query >/dev/null 2>&1; then
        local package status
        for package in ca-certificates curl git build-essential; do
            status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
            [ "$status" = 'install ok installed' ] || return 1
        done
        return 0
    fi

    # 非 Debian 测试宿主没有 dpkg-query；用等价命令能力维持 dry-run fixture 可移植性。
    local command_name
    for command_name in curl git cc make; do
        command -v "$command_name" >/dev/null 2>&1 || return 1
    done
    return 0
}

# 功能：判断 Arch Stage 0 的最小 pacman 前置是否完整。
# 参数：无。
# 返回：0 全部已安装，1 至少缺少一个前置包。
stage0_pacman_prerequisites_ready() {
    if [ "${POWERSHELL_SCRIPTS_FORCE_MISSING_PACMAN_PREREQUISITES:-}" = '1' ]; then
        return 1
    fi

    if command -v pacman >/dev/null 2>&1; then
        local package
        for package in base-devel ca-certificates curl git; do
            pacman -Q "$package" >/dev/null 2>&1 || return 1
        done
        return 0
    fi

    local command_name
    for command_name in curl git cc make; do
        command -v "$command_name" >/dev/null 2>&1 || return 1
    done
    return 0
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-url)
            [ "$#" -ge 2 ] || linux_install_fail '--repo-url 需要一个值' 2
            REPO_URL="$2"
            shift 2
            ;;
        --repo-dir)
            [ "$#" -ge 2 ] || linux_install_fail '--repo-dir 需要一个值' 2
            REPO_DIR="$2"
            shift 2
            ;;
        --preset)
            [ "$#" -ge 2 ] || linux_install_fail '--preset 需要一个值' 2
            PRESET="$2"
            shift 2
            ;;
        --network-mode)
            [ "$#" -ge 2 ] || linux_install_fail '--network-mode 需要一个值' 2
            NETWORK_MODE="$2"
            shift 2
            ;;
        --powershell-package)
            [ "$#" -ge 2 ] || linux_install_fail '--powershell-package 需要一个值' 2
            POWERSHELL_PACKAGE="$2"
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

linux_install_value_in "$PRESET" Core Full || linux_install_fail "不支持的 preset: $PRESET" 2
linux_install_value_in "$NETWORK_MODE" Direct China Auto || linux_install_fail "不支持的 network mode: $NETWORK_MODE" 2
[ "$UNATTENDED" != true ] || [ "$NON_INTERACTIVE" != true ] || linux_install_fail '--unattended 与 --non-interactive 不能同时使用' 2
linux_install_detect_platform || linux_install_fail 'Linux bootstrap 只能在 Linux/WSL 中运行' 10
[ "$LI_ARCHITECTURE" = 'amd64' ] || linux_install_fail "首期不支持架构: $LI_ARCHITECTURE" 10
linux_install_value_in "$LI_DISTRIBUTION_FAMILY" debian arch || linux_install_fail "Stage 0 不支持发行版: $LI_DISTRIBUTION_ID" 10

if [ -n "$POWERSHELL_PACKAGE" ] && [ ! -f "$POWERSHELL_PACKAGE" ]; then
    linux_install_fail "PowerShell deb 不存在: $POWERSHELL_PACKAGE" 2
fi

repo_root=''
if [ -f "$SCRIPT_DIR/../install.ps1" ]; then
    repo_root="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
else
    repo_root="$REPO_DIR"
fi

prerequisites_ready=true
if [ "${POWERSHELL_SCRIPTS_FORCE_MISSING_GIT:-}" = '1' ]; then
    prerequisites_ready=false
elif [ "$LI_DISTRIBUTION_FAMILY" = 'arch' ]; then
    stage0_pacman_prerequisites_ready || prerequisites_ready=false
else
    stage0_apt_prerequisites_ready || prerequisites_ready=false
fi
if [ "$prerequisites_ready" = false ]; then
    if [ "$NETWORK_MODE" != 'Direct' ]; then
        linux_install_fail 'China/Auto 在系统包前置不完整时没有可恢复的 Stage 0 adapter；请预装发行版前置或使用 Direct' 10
    fi
    linux_install_prepare_sudo "$UNATTENDED" "$NON_INTERACTIVE" "$DRY_RUN" ||
        linux_install_fail '当前交互模式无法获得 sudo 权限' 10
    if [ "$DRY_RUN" = true ]; then
        if [ "$LI_DISTRIBUTION_FAMILY" = 'arch' ]; then
            linux_install_print_command sudo pacman -Syu --needed --noconfirm base-devel ca-certificates curl git
        else
            linux_install_print_command sudo apt-get update
            linux_install_print_command sudo apt-get install -y ca-certificates curl git build-essential
        fi
    else
        if [ "$LI_DISTRIBUTION_FAMILY" = 'arch' ]; then
            sudo pacman -Syu --needed --noconfirm base-devel ca-certificates curl git
        else
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl git build-essential
        fi
    fi
fi

if [ ! -d "$repo_root/.git" ]; then
    if [ -e "$repo_root" ] && [ ! -d "$repo_root" ]; then
        linux_install_fail "repo-dir 不是目录: $repo_root" 2
    fi
    if [ "$DRY_RUN" = true ]; then
        linux_install_print_command git clone --depth=1 "$REPO_URL" "$repo_root"
    else
        mkdir -p "$(dirname -- "$repo_root")"
        git clone --depth=1 "$REPO_URL" "$repo_root"
    fi
fi

brew_args=(--network-mode "$NETWORK_MODE")
pwsh_args=(--network-mode "$NETWORK_MODE")
root_args=(-NoLogo -NoProfile -File "$repo_root/install.ps1" -Preset "$PRESET" -NetworkMode "$NETWORK_MODE")
if [ -n "$POWERSHELL_PACKAGE" ]; then
    pwsh_args+=(--package "$POWERSHELL_PACKAGE")
fi
if [ "$UNATTENDED" = true ]; then
    brew_args+=(--unattended)
    pwsh_args+=(--unattended)
    root_args+=(-Unattended)
fi
if [ "$NON_INTERACTIVE" = true ]; then
    brew_args+=(--non-interactive)
    pwsh_args+=(--non-interactive)
    root_args+=(-NonInteractive)
fi
if [ "$DRY_RUN" = true ]; then
    linux_install_print_command bash "$repo_root/linux/01installHomeBrew.sh" "${brew_args[@]}" --dry-run
    linux_install_print_command bash "$repo_root/linux/02installPowerShell.sh" "${pwsh_args[@]}" --dry-run
    linux_install_print_command pwsh "${root_args[@]}" -WhatIf
    exit 0
fi

bash "$repo_root/linux/01installHomeBrew.sh" "${brew_args[@]}"
bash "$repo_root/linux/02installPowerShell.sh" "${pwsh_args[@]}"
command -v pwsh >/dev/null 2>&1 || linux_install_fail 'Stage 0 完成后仍找不到 PowerShell 7' 10
pwsh "${root_args[@]}"
