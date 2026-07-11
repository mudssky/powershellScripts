#!/usr/bin/env zsh

set -euo pipefail

REPO_URL='https://github.com/mudssky/powershellScripts.git'
REPO_DIR="${POWERSHELL_SCRIPTS_REPO_DIR:-$HOME/powershellScripts}"
PRESET='Core'
NETWORK_MODE='Direct'
UNATTENDED=false
NON_INTERACTIVE=false
DRY_RUN=false

# 功能：输出 macOS Stage 0 bootstrap 帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: 00bootstrap.zsh [options]

Options:
  --repo-url <url>                   仓库地址
  --repo-dir <path>                  clone 目录
  --preset Core|Full                 Stage 1 预设，默认 Core
  --network-mode Direct|China|Auto   网络模式，默认 Direct
  --unattended                       允许开头一次 sudo 认证
  --non-interactive                  严格零提示，前置不足返回 10
  --dry-run                          预览 Stage 0 和根 Stage 1
  -h, --help                         显示帮助
EOF
}

# 功能：输出错误并以指定退出码结束。
# 参数：$1 消息，$2 可选退出码。
# 返回：不返回。
fail() {
    print -u2 -- "$1"
    exit "${2:-1}"
}

# 功能：在无人值守场景安装 Command Line Tools。
# 参数：无。
# 返回：0 安装完成；10 无可用更新或安装失败。
install_clt_headless() {
    local marker='/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress'
    local label
    touch "$marker"
    label="$(softwareupdate -l 2>/dev/null | sed -n 's/^[[:space:]]*\* Label: \(Command Line Tools.*\)$/\1/p' | tail -n 1)"
    rm -f "$marker"
    [[ -n "$label" ]] || return 10
    sudo softwareupdate -i "$label" --verbose || return 10
    sudo xcode-select --switch /Library/Developer/CommandLineTools || return 10
}

while (( $# > 0 )); do
    case "$1" in
        --repo-url)
            [[ $# -ge 2 ]] || fail '--repo-url 需要一个值' 2
            REPO_URL="$2"
            shift 2
            ;;
        --repo-dir)
            [[ $# -ge 2 ]] || fail '--repo-dir 需要一个值' 2
            REPO_DIR="$2"
            shift 2
            ;;
        --preset)
            [[ $# -ge 2 ]] || fail '--preset 需要一个值' 2
            PRESET="$2"
            shift 2
            ;;
        --network-mode)
            [[ $# -ge 2 ]] || fail '--network-mode 需要一个值' 2
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
            fail "未知参数: $1" 2
            ;;
    esac
done

[[ "$PRESET" == 'Core' || "$PRESET" == 'Full' ]] || fail "不支持的 preset: $PRESET" 2
[[ "$NETWORK_MODE" == 'Direct' || "$NETWORK_MODE" == 'China' || "$NETWORK_MODE" == 'Auto' ]] || fail "不支持的 network mode: $NETWORK_MODE" 2
[[ "$UNATTENDED" != true || "$NON_INTERACTIVE" != true ]] || fail '--unattended 与 --non-interactive 不能同时使用' 2
[[ "$(uname -s)" == 'Darwin' ]] || fail 'macOS bootstrap 只能在 macOS 运行' 10
command -v curl >/dev/null 2>&1 || fail '缺少 curl' 10

if [[ "$DRY_RUN" != true ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        sudo -n true >/dev/null 2>&1 || fail '严格非交互模式需要预置 sudo 凭据' 10
    elif [[ "$UNATTENDED" == true ]]; then
        sudo -v || fail '无法获得管理员认证' 10
    fi
fi

script_dir="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
if [[ -f "$script_dir/../install.ps1" ]]; then
    repo_root="$(cd -- "$script_dir/.." >/dev/null 2>&1 && pwd)"
else
    repo_root="$REPO_DIR"
    if ! command -v git >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == true ]]; then
            print -- '[DRY] 安装 Command Line Tools 以获得 Git'
        elif [[ "$NON_INTERACTIVE" == true || "$UNATTENDED" == true ]]; then
            install_clt_headless || fail '无法无交互安装 Command Line Tools' 10
        else
            xcode-select --install >/dev/null 2>&1 || true
            fail '已请求安装 Command Line Tools，完成后重新运行 bootstrap' 10
        fi
    fi

    if [[ ! -d "$repo_root/.git" ]]; then
        if [[ -e "$repo_root" && ! -d "$repo_root" ]]; then
            fail "repo-dir 不是目录: $repo_root" 2
        fi
        if [[ "$DRY_RUN" == true ]]; then
            print -- "[DRY] git clone --depth=1 $REPO_URL $repo_root"
            exit 0
        fi
        mkdir -p "$(dirname -- "$repo_root")"
        git clone --depth=1 "$REPO_URL" "$repo_root"
    fi
fi

interaction_args=()
if [[ "$UNATTENDED" == true ]]; then
    interaction_args+=(--unattended)
elif [[ "$NON_INTERACTIVE" == true ]]; then
    interaction_args+=(--non-interactive)
fi
preview_args=()
if [[ "$DRY_RUN" == true ]]; then
    preview_args+=(--dry-run)
fi

zsh "$repo_root/macos/01installHomebrew.zsh" --network-mode "$NETWORK_MODE" "${interaction_args[@]}" "${preview_args[@]}"
zsh "$repo_root/macos/02installPowerShell.zsh" --network-mode "$NETWORK_MODE" "${interaction_args[@]}" "${preview_args[@]}"

if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
command -v pwsh >/dev/null 2>&1 || fail 'Stage 0 完成后仍找不到 PowerShell 7' 10

root_args=(-NoLogo -NoProfile -File "$repo_root/install.ps1" -Preset "$PRESET" -NetworkMode "$NETWORK_MODE")
if [[ "$UNATTENDED" == true ]]; then
    root_args+=(-Unattended)
elif [[ "$NON_INTERACTIVE" == true ]]; then
    root_args+=(-NonInteractive)
fi
if [[ "$DRY_RUN" == true ]]; then
    root_args+=(-WhatIf)
fi

pwsh "${root_args[@]}"
