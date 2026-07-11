#!/usr/bin/env bash

set -euo pipefail

NETWORK_MODE='Direct'
TRANSACTION_ID=''
OUTPUT_FORMAT='Text'
DRY_RUN=false

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=linux/lib/install-common.sh
source "$SCRIPT_DIR/lib/install-common.sh"

# 功能：输出 Linux Stage 1 source 入口帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: 03configureSources.sh [options]

Options:
  --network-mode Direct|China|Auto  网络模式，默认 Direct
  --transaction-id <id>            根编排器 source 事务 ID
  --output-format Text|Json         输出格式，默认 Text
  --unattended                      接受根编排器交互参数
  --non-interactive                 接受根编排器交互参数
  --dry-run                         映射为 Switch-Mirrors -WhatIf
  -h, --help                        显示帮助
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --network-mode)
            [ "$#" -ge 2 ] || linux_install_fail '--network-mode 需要一个值' 2
            NETWORK_MODE="$2"
            shift 2
            ;;
        --transaction-id)
            [ "$#" -ge 2 ] || linux_install_fail '--transaction-id 需要一个值' 2
            TRANSACTION_ID="$2"
            shift 2
            ;;
        --output-format)
            [ "$#" -ge 2 ] || linux_install_fail '--output-format 需要一个值' 2
            OUTPUT_FORMAT="$2"
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

linux_install_value_in "$NETWORK_MODE" Direct China Auto || linux_install_fail "不支持的 network mode: $NETWORK_MODE" 2
case "$OUTPUT_FORMAT" in
    Text|text) OUTPUT_FORMAT='Text' ;;
    Json|json) OUTPUT_FORMAT='Json' ;;
    *) linux_install_fail "不支持的 output format: $OUTPUT_FORMAT" 2 ;;
esac
linux_install_detect_platform || linux_install_fail 'Linux source 步骤只能在 Linux/WSL 中运行' 10
[ "$LI_ARCHITECTURE" = 'amd64' ] || linux_install_fail "首期不支持架构: $LI_ARCHITECTURE" 10
linux_install_value_in "$LI_DISTRIBUTION_ID" ubuntu debian arch ||
    linux_install_fail "没有可用的 package source target: $LI_DISTRIBUTION_ID" 10
command -v pwsh >/dev/null 2>&1 || linux_install_fail '缺少 PowerShell 7，无法进入 Stage 1 source 引擎' 10

source_helper="$SCRIPT_DIR/pwsh/Invoke-LinuxSources.ps1"
[ -f "$source_helper" ] || linux_install_fail "Linux source helper 不存在: $source_helper" 10
arguments=(-NoLogo -NoProfile -File "$source_helper" -DistributionTarget "$LI_DISTRIBUTION_ID" -NetworkMode "$NETWORK_MODE" -OutputFormat "$OUTPUT_FORMAT")
if [ -n "$TRANSACTION_ID" ]; then
    arguments+=(-TransactionId "$TRANSACTION_ID")
fi
if [ "$DRY_RUN" = true ]; then
    arguments+=(-WhatIf)
fi
pwsh "${arguments[@]}"
