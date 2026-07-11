#!/usr/bin/env zsh

set -euo pipefail

NETWORK_MODE='Direct'
TRANSACTION_ID=''
OUTPUT_FORMAT='Text'
DRY_RUN=false

# 功能：输出 macOS Stage 1 source 薄入口帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: 03configureSources.zsh [options]

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

# 功能：输出错误并结束。
# 参数：$1 消息，$2 可选退出码。
# 返回：不返回。
fail() {
    print -u2 -- "$1"
    exit "${2:-1}"
}

while (( $# > 0 )); do
    case "$1" in
        --network-mode)
            [[ $# -ge 2 ]] || fail '--network-mode 需要一个值' 2
            NETWORK_MODE="$2"
            shift 2
            ;;
        --transaction-id)
            [[ $# -ge 2 ]] || fail '--transaction-id 需要一个值' 2
            TRANSACTION_ID="$2"
            shift 2
            ;;
        --output-format)
            [[ $# -ge 2 ]] || fail '--output-format 需要一个值' 2
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
            fail "未知参数: $1" 2
            ;;
    esac
done

[[ "$NETWORK_MODE" == 'Direct' || "$NETWORK_MODE" == 'China' || "$NETWORK_MODE" == 'Auto' ]] || fail "不支持的 network mode: $NETWORK_MODE" 2
[[ "$OUTPUT_FORMAT" == 'Text' || "$OUTPUT_FORMAT" == 'Json' || "$OUTPUT_FORMAT" == 'text' || "$OUTPUT_FORMAT" == 'json' ]] || fail "不支持的 output format: $OUTPUT_FORMAT" 2
command -v pwsh >/dev/null 2>&1 || fail '缺少 PowerShell 7，无法进入 Stage 1 source 引擎' 10

script_dir="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
switch_mirrors="$script_dir/../scripts/pwsh/misc/Switch-Mirrors.ps1"
[[ -f "$switch_mirrors" ]] || fail "source 引擎不存在: $switch_mirrors" 10

normalized_output='Text'
if [[ "$OUTPUT_FORMAT" == 'Json' || "$OUTPUT_FORMAT" == 'json' ]]; then
    normalized_output='Json'
fi

arguments=(
    -NoLogo -NoProfile -File "$switch_mirrors"
    -Action Apply
    -Mode "$NETWORK_MODE"
    -Phase Runtime
    -Target brew
    -OutputFormat "$normalized_output"
)
if [[ -n "$TRANSACTION_ID" ]]; then
    arguments+=(-TransactionId "$TRANSACTION_ID")
fi
if [[ "$DRY_RUN" == true ]]; then
    arguments+=(-WhatIf)
fi

pwsh "${arguments[@]}"
