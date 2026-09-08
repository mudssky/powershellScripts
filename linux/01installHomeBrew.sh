#!/usr/bin/env bash

set -euo pipefail

NETWORK_MODE='Direct'
UNATTENDED=false
NON_INTERACTIVE=false
DRY_RUN=false

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=linux/lib/install-common.sh
source "$SCRIPT_DIR/lib/install-common.sh"

# 功能：输出 Linuxbrew 安装步骤帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: 01installHomeBrew.sh [options]

安装或检测成功后会把 brew shellenv 持久化到登录 profile
（bash: ~/.profile，zsh: ~/.zprofile），已存在时跳过。

Options:
  --network-mode Direct|China|Auto  Stage 0 网络模式，默认 Direct
  --unattended                     允许开头一次 sudo 认证
  --non-interactive                严格零提示
  --dry-run                        只显示计划
  -h, --help                       显示帮助
EOF
}

# 功能：定位现有 Linuxbrew 可执行文件。
# 参数：无。
# 返回：0 并输出路径，1 未找到。
find_linuxbrew() {
    if [ "${POWERSHELL_SCRIPTS_FORCE_MISSING_BREW:-}" != '1' ] && command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
    fi
    local candidate
    for candidate in /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
        if [ "${POWERSHELL_SCRIPTS_FORCE_MISSING_BREW:-}" != '1' ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# 功能：加载 brew shellenv 并验证 prefix。
# 参数：$1 brew 可执行文件。
# 返回：0 验证成功，非零表示 shellenv 或 prefix 失败。
load_linuxbrew_environment() {
    local brew_path="$1"
    eval "$("$brew_path" shellenv)"
    brew --prefix >/dev/null
}

# 功能：把 brew shellenv 持久化到登录 profile，保证新登录 shell 与安装流水线
#       子进程能看到 Linuxbrew 工具；bash 登录路径为 ~/.profile，zsh 为 ~/.zprofile。
#       幂等：目标文件已包含 shellenv 行时跳过；写前按仓库约定生成带可读时间戳的
#       .bak 备份；dry-run 只打印计划。
# 参数：$1 brew 可执行文件。
# 返回：0 已持久化、已存在或 dry-run；备份或写文件失败时非零。
persist_linuxbrew_shellenv() {
    local brew_path="$1"
    local shell_name target_file
    shell_name="$(basename -- "${SHELL:-bash}")"
    case "$shell_name" in
        zsh) target_file="$HOME/.zprofile" ;;
        *) target_file="$HOME/.profile" ;;
    esac

    if grep -Fq 'brew shellenv' "$target_file" 2>/dev/null; then
        printf '%s 已包含 Homebrew shellenv，跳过持久化\n' "$target_file"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        printf '[DRY] 向 %s 写入 Homebrew shellenv\n' "$target_file"
        return 0
    fi

    if [ -e "$target_file" ]; then
        local timestamp backup_path
        timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
        backup_path="${target_file}.${timestamp}.bak"
        cp -p "$target_file" "$backup_path"
        printf '已备份现有配置: %s\n' "$backup_path"
    fi
    {
        printf '\n'
        printf '# Load Homebrew shellenv (managed by powershellScripts)\n'
        printf 'eval "$(%s shellenv)"\n' "$brew_path"
    } >> "$target_file"
    printf '已将 Homebrew shellenv 写入 %s\n' "$target_file"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --network-mode)
            [ "$#" -ge 2 ] || linux_install_fail '--network-mode 需要一个值' 2
            NETWORK_MODE="$2"
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
linux_install_detect_platform || linux_install_fail 'Linuxbrew 步骤只能在 Linux/WSL 中运行' 10
[ "$LI_ARCHITECTURE" = 'amd64' ] || linux_install_fail "首期不支持架构: $LI_ARCHITECTURE" 10

if brew_path="$(find_linuxbrew)"; then
    load_linuxbrew_environment "$brew_path"
    persist_linuxbrew_shellenv "$brew_path"
    printf 'Linuxbrew 已就绪: %s\n' "$(brew --prefix)"
    exit 0
fi

command -v curl >/dev/null 2>&1 || linux_install_fail '缺少 curl，无法下载 Homebrew 安装器' 10
linux_install_prepare_sudo "$UNATTENDED" "$NON_INTERACTIVE" "$DRY_RUN" ||
    linux_install_fail '当前交互模式无法获得 sudo 权限' 10

repo_root="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
bootstrap_helper="$repo_root/scripts/bash/package-source-bootstrap.sh"
[ -f "$bootstrap_helper" ] || linux_install_fail "Stage 0 source helper 不存在: $bootstrap_helper" 10

if [ "$DRY_RUN" = true ]; then
    printf '[DRY] 下载 Homebrew 官方安装器\n'
    bash "$bootstrap_helper" --mode "$NETWORK_MODE" --target brew --dry-run -- /bin/bash /tmp/homebrew-install.sh
    exit $?
fi

installer_path="$(mktemp -t powershellScripts-homebrew.XXXXXX)"
trap 'rm -f "$installer_path"' EXIT
curl -fsSL 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' -o "$installer_path"

install_command=(/bin/bash "$installer_path")
if [ "$UNATTENDED" = true ] || [ "$NON_INTERACTIVE" = true ]; then
    install_command=(env NONINTERACTIVE=1 /bin/bash "$installer_path")
fi
bash "$bootstrap_helper" --mode "$NETWORK_MODE" --target brew -- "${install_command[@]}"

brew_path="$(find_linuxbrew)" || linux_install_fail 'Homebrew 安装完成后仍找不到 brew'
load_linuxbrew_environment "$brew_path"
persist_linuxbrew_shellenv "$brew_path"
printf 'Linuxbrew 安装完成: %s\n' "$(brew --prefix)"
