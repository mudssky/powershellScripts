#!/usr/bin/env bash

set -euo pipefail

PRESET='Core'
SHELL_TYPE=''
DRY_RUN=false
EXCLUDES=()
EXCLUDE_COUNT=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=linux/lib/install-common.sh
source "$SCRIPT_DIR/lib/install-common.sh"

# 功能：输出 Linux shell 配置部署帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: 04deployShellConfig.sh [options]

Options:
  --preset Core|Full     由根编排器透传
  --shell bash|zsh       显式目标 shell，默认按 SHELL 探测
  --exclude <pattern>    排除配置片段，可重复
  --unattended           接受根编排器交互参数
  --non-interactive      接受根编排器交互参数
  --dry-run              只显示计划
  -h, --help             显示帮助
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --preset)
            [ "$#" -ge 2 ] || linux_install_fail '--preset 需要一个值' 2
            PRESET="$2"
            shift 2
            ;;
        --shell)
            [ "$#" -ge 2 ] || linux_install_fail '--shell 需要一个值' 2
            SHELL_TYPE="$2"
            shift 2
            ;;
        --exclude)
            [ "$#" -ge 2 ] || linux_install_fail '--exclude 需要一个值' 2
            EXCLUDES+=("$2")
            EXCLUDE_COUNT=$((EXCLUDE_COUNT + 1))
            shift 2
            ;;
        --unattended|--non-interactive)
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
if [ -z "$SHELL_TYPE" ]; then
    SHELL_TYPE="$(basename -- "${SHELL:-bash}")"
fi
linux_install_value_in "$SHELL_TYPE" bash zsh || SHELL_TYPE='bash'

deploy_script="$SCRIPT_DIR/../shell/deploy.sh"
[ -f "$deploy_script" ] || linux_install_fail "shell 部署入口不存在: $deploy_script"
arguments=(--shell "$SHELL_TYPE")
if [ "$DRY_RUN" = true ]; then
    arguments+=(--dry-run)
fi
if [ "$EXCLUDE_COUNT" -gt 0 ]; then
    for pattern in "${EXCLUDES[@]}"; do
        arguments+=(--exclude "$pattern")
    done
fi
bash "$deploy_script" "${arguments[@]}"
