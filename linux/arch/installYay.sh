#!/usr/bin/env bash

set -euo pipefail

UNATTENDED=false
NON_INTERACTIVE=false
DRY_RUN=false

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=linux/lib/install-common.sh
source "$SCRIPT_DIR/../lib/install-common.sh"

# 功能：输出 Arch Linux yay 可选安装器帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: installYay.sh [options]

Options:
  --unattended       允许开头一次 sudo 认证
  --non-interactive  严格零提示，sudo 前置不足时返回 10
  --dry-run          只显示 pacman、clone 与 makepkg 计划
  -h, --help         显示帮助
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
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

[ "$UNATTENDED" != true ] || [ "$NON_INTERACTIVE" != true ] || linux_install_fail '--unattended 与 --non-interactive 不能同时使用' 2
linux_install_detect_platform || linux_install_fail 'yay 安装器只能在 Linux 中运行' 10
[ "$LI_DISTRIBUTION_FAMILY" = 'arch' ] || linux_install_fail "yay 安装器只支持 Arch Linux: $LI_DISTRIBUTION_ID" 10
[ "$LI_ARCHITECTURE" = 'amd64' ] || linux_install_fail "yay 安装器暂不支持架构: $LI_ARCHITECTURE" 10
if [ "$DRY_RUN" != true ] && [ "$(id -u)" -eq 0 ]; then
    linux_install_fail 'makepkg 不允许以 root 用户运行，请使用普通用户执行' 2
fi

if [ "${POWERSHELL_SCRIPTS_FORCE_MISSING_YAY:-}" != '1' ] && command -v yay >/dev/null 2>&1; then
    printf 'yay 已就绪: %s\n' "$(yay --version | head -n 1)"
    exit 0
fi

linux_install_prepare_sudo "$UNATTENDED" "$NON_INTERACTIVE" "$DRY_RUN" ||
    linux_install_fail '当前交互模式无法获得 sudo 权限' 10

if [ "$DRY_RUN" = true ]; then
    linux_install_print_command sudo pacman -S --needed --noconfirm base-devel git
    linux_install_print_command git clone https://aur.archlinux.org/yay.git '<temporary-directory>/yay'
    linux_install_print_command makepkg -si --needed --noconfirm
    exit 0
fi

sudo pacman -S --needed --noconfirm base-devel git
work_dir="$(mktemp -d -t powershellScripts-yay.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
git clone --depth=1 https://aur.archlinux.org/yay.git "$work_dir/yay"
(
    cd "$work_dir/yay"
    makepkg -si --needed --noconfirm
)
command -v yay >/dev/null 2>&1 || linux_install_fail 'yay 安装后验证失败'
printf 'yay 安装完成: %s\n' "$(yay --version | head -n 1)"
