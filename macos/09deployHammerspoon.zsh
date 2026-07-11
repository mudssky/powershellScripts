#!/bin/zsh

# macOS Hammerspoon 部署叶子入口。
# 功能：把参数原样交给唯一的 Hammerspoon loader，不修改仓库文件权限。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOAD_SCRIPT="$SCRIPT_DIR/hammerspoon/load_scripts.zsh"
UNATTENDED=false
NON_INTERACTIVE=false
FORWARD_ARGS=()

# 显示 Hammerspoon 部署叶子帮助。
# 入参：无。
# 返回值：无。
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --preset Core|Full     由根编排器透传；本步骤只在 Full 注册
  --unattended           接受根编排器交互模式参数
  --non-interactive      接受根编排器交互模式参数
  --dry-run              只显示计划，不写入或启动 GUI
  --no-launch            部署后不启动或重启 Hammerspoon
  --install              未安装时使用 Homebrew Cask 安装
  -h, --help             显示帮助
EOF
}

if [ ! -f "$LOAD_SCRIPT" ]; then
    echo "[ERROR] 未找到 Hammerspoon loader: $LOAD_SCRIPT" >&2
    exit 1
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --preset)
            [ $# -ge 2 ] || { echo "[ERROR] --preset 需要一个值" >&2; exit 2; }
            [ "$2" = "Core" ] || [ "$2" = "Full" ] || { echo "[ERROR] --preset 只支持 Core 或 Full" >&2; exit 2; }
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
        -h|--help)
            usage
            exit 0
            ;;
        *)
            FORWARD_ARGS+=("$1")
            shift
            ;;
    esac
done

if [ "$UNATTENDED" = true ] && [ "$NON_INTERACTIVE" = true ]; then
    echo "[ERROR] unattended 与 non-interactive 不能同时使用" >&2
    exit 2
fi

exec zsh "$LOAD_SCRIPT" "${FORWARD_ARGS[@]}"
