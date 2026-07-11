#!/usr/bin/env zsh

set -euo pipefail

NETWORK_MODE='Direct'
DRY_RUN=false
UNATTENDED=false
NON_INTERACTIVE=false

# 功能：输出 PowerShell 安装步骤帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: 02installPowerShell.zsh [options]

Options:
  --network-mode Direct|China|Auto  Stage 0 网络模式，默认 Direct
  --unattended                     无人值守模式
  --non-interactive                严格非交互模式
  --dry-run                        只显示计划，不安装或升级
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

# 功能：定位 Homebrew 并加载其 shellenv。
# 参数：无。
# 返回：0 成功并输出 brew 路径；10 未安装。
prepare_brew() {
    local candidate
    if command -v brew >/dev/null 2>&1; then
        candidate="$(command -v brew)"
    elif [[ -x /opt/homebrew/bin/brew ]]; then
        candidate=/opt/homebrew/bin/brew
    elif [[ -x /usr/local/bin/brew ]]; then
        candidate=/usr/local/bin/brew
    else
        return 10
    fi
    eval "$("$candidate" shellenv)"
    BREW_PATH="$(command -v brew)"
}

# 功能：判断当前 pwsh 是否满足主版本 7 基线。
# 参数：无。
# 返回：0 满足；1 不满足或不可用。
test_pwsh7() {
    command -v pwsh >/dev/null 2>&1 || return 1
    local major
    major="$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>/dev/null)" || return 1
    [[ "$major" == <-> && "$major" -ge 7 ]]
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
[[ "$(uname -s)" == 'Darwin' ]] || fail 'PowerShell macOS 步骤只能在 macOS 运行' 10

BREW_PATH=''
if ! prepare_brew; then
    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$(uname -m)" == 'arm64' ]]; then
            BREW_PATH='/opt/homebrew/bin/brew'
        else
            BREW_PATH='/usr/local/bin/brew'
        fi
        print -- "[DRY] 假定 01 完成后 Homebrew 位于 $BREW_PATH"
    else
        fail '缺少 Homebrew，请先运行 01installHomebrew.zsh' 10
    fi
fi
if test_pwsh7; then
    print -- "PowerShell 7 已就绪: $(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
    exit 0
fi

repo_root="$(cd -- "$(dirname -- "$0")/.." >/dev/null 2>&1 && pwd)"
bootstrap_helper="$repo_root/scripts/bash/package-source-bootstrap.sh"
[[ -f "$bootstrap_helper" ]] || fail "Stage 0 source helper 不存在: $bootstrap_helper"

brew_action=(install --cask powershell)
if [[ "$DRY_RUN" != true ]] && brew list --cask powershell >/dev/null 2>&1; then
    brew_action=(upgrade --cask powershell)
fi

if [[ "$DRY_RUN" == true ]]; then
    print -- "[DRY] $BREW_PATH ${brew_action[*]}"
    bash "$bootstrap_helper" --mode "$NETWORK_MODE" --target brew --dry-run -- "$BREW_PATH" "${brew_action[@]}"
    exit $?
fi

HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 \
    bash "$bootstrap_helper" --mode "$NETWORK_MODE" --target brew -- "$BREW_PATH" "${brew_action[@]}"
hash -r
test_pwsh7 || fail 'PowerShell 安装后版本验证失败'
print -- "PowerShell 安装完成: $(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
