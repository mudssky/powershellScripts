#!/usr/bin/env zsh

set -euo pipefail

NETWORK_MODE='Direct'
DRY_RUN=false
UNATTENDED=false
NON_INTERACTIVE=false

# 功能：输出 Homebrew 安装步骤帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: 01installHomebrew.zsh [options]

Options:
  --network-mode Direct|China|Auto  Stage 0 网络模式，默认 Direct
  --unattended                     允许开头一次 sudo 认证，之后禁止隐藏提示
  --non-interactive                严格零提示，sudo 前置不足时返回 10
  --dry-run                        只显示计划，不下载或安装
  -h, --help                       显示帮助
EOF
}

# 功能：输出错误并以指定退出码结束。
# 参数：$1 消息，$2 可选退出码。
# 返回：不返回。
fail() {
    print -u2 -- "$1"
    exit "${2:-1}"
}

# 功能：定位现有 Homebrew 可执行文件。
# 参数：无。
# 返回：0 并输出路径；未找到返回 1。
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

# 功能：把实际 Homebrew prefix 注入当前进程并验证。
# 参数：$1 brew 可执行文件路径。
# 返回：0 成功；1 shellenv 或 prefix 验证失败。
load_brew_environment() {
    local brew_path="$1"
    eval "$("$brew_path" shellenv)"
    brew --prefix >/dev/null
}

while (( $# > 0 )); do
    case "$1" in
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

[[ "$NETWORK_MODE" == 'Direct' || "$NETWORK_MODE" == 'China' || "$NETWORK_MODE" == 'Auto' ]] || fail "不支持的 network mode: $NETWORK_MODE" 2
[[ "$UNATTENDED" != true || "$NON_INTERACTIVE" != true ]] || fail '--unattended 与 --non-interactive 不能同时使用' 2
[[ "$(uname -s)" == 'Darwin' ]] || fail 'Homebrew macOS 步骤只能在 macOS 运行' 10

if brew_path="$(find_brew)"; then
    load_brew_environment "$brew_path"
    print -- "Homebrew 已就绪: $(brew --prefix)"
    exit 0
fi

command -v curl >/dev/null 2>&1 || fail '缺少 curl，无法下载安装器' 10
if [[ "$NON_INTERACTIVE" == true && "$DRY_RUN" != true ]]; then
    sudo -n true >/dev/null 2>&1 || fail '严格非交互模式需要预置 sudo 凭据' 10
elif [[ "$UNATTENDED" == true && "$DRY_RUN" != true ]]; then
    sudo -v || fail '无法获得管理员认证' 10
fi

repo_root="$(cd -- "$(dirname -- "$0")/.." >/dev/null 2>&1 && pwd)"
bootstrap_helper="$repo_root/scripts/bash/package-source-bootstrap.sh"
[[ -f "$bootstrap_helper" ]] || fail "Stage 0 source helper 不存在: $bootstrap_helper"

if [[ "$DRY_RUN" == true ]]; then
    print -- "[DRY] 下载 Homebrew 官方安装器"
    bash "$bootstrap_helper" --mode "$NETWORK_MODE" --target brew --dry-run -- /bin/bash /tmp/homebrew-install.sh
    exit $?
fi

installer_path="$(mktemp -t powershellScripts-homebrew)"
trap 'rm -f "$installer_path"' EXIT
curl -fsSL 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' -o "$installer_path"

install_command=(/bin/bash "$installer_path")
if [[ "$UNATTENDED" == true || "$NON_INTERACTIVE" == true ]]; then
    install_command=(env NONINTERACTIVE=1 /bin/bash "$installer_path")
fi
bash "$bootstrap_helper" --mode "$NETWORK_MODE" --target brew -- "${install_command[@]}"

brew_path="$(find_brew)" || fail 'Homebrew 安装完成后仍找不到 brew'
load_brew_environment "$brew_path"
print -- "Homebrew 安装完成: $(brew --prefix)"
