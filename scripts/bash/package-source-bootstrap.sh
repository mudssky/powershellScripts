#!/usr/bin/env bash

set -euo pipefail

MODE='Direct'
TARGET='brew'
CONFIG_PATH=''
DRY_RUN=false
OUTPUT_FORMAT='Text'
COMMAND=()

# 功能：输出 Stage 0 helper 使用说明。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage:
  package-source-bootstrap.sh --mode Direct|China|Auto --target brew [options] -- command [args...]

Options:
  --config <path>       Stage 0 env 配置路径
  --dry-run             只显示决策，不执行命令
  --output Text|Json    输出格式，默认 Text
  -h, --help            显示帮助
EOF
}

# 功能：输出结构化或文本状态。
# 参数：$1 状态，$2 原因，$3 是否注入镜像。
# 返回：无，内容写入 stderr，避免污染被包装命令的 stdout。
emit_status() {
    local status="$1"
    local reason="$2"
    local mirrored="$3"

    if [ "$OUTPUT_FORMAT" = 'Json' ]; then
        printf '{"schemaVersion":1,"mode":"%s","target":"%s","status":"%s","mirrored":%s,"reason":"%s"}\n' \
            "$MODE" "$TARGET" "$status" "$mirrored" "$reason" >&2
        return
    fi
    printf '[%s] %s: %s\n' "$status" "$TARGET" "$reason" >&2
}

# 功能：严格读取 Homebrew Stage 0 HTTPS 配置。
# 参数：$1 KEY=VALUE 配置文件。
# 返回：0 成功；10 缺少或包含非法必需值。
load_brew_bootstrap_config() {
    local file_path="$1"
    local line name value

    if [ ! -r "$file_path" ]; then
        printf 'Stage 0 配置不可读: %s\n' "$file_path" >&2
        return 10
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|'#'*)
                continue
                ;;
            *=*)
                name="${line%%=*}"
                value="${line#*=}"
                ;;
            *)
                printf 'Stage 0 配置包含非法行\n' >&2
                return 10
                ;;
        esac

        case "$name" in
            HOMEBREW_BREW_GIT_REMOTE|HOMEBREW_CORE_GIT_REMOTE|HOMEBREW_API_DOMAIN|HOMEBREW_BOTTLE_DOMAIN)
                ;;
            *)
                continue
                ;;
        esac
        case "$value" in
            https://*)
                ;;
            *)
                printf 'Stage 0 配置只允许 HTTPS: %s\n' "$name" >&2
                return 10
                ;;
        esac
        case "$value" in
            *[[:space:]]*)
                printf 'Stage 0 配置值不能包含空白: %s\n' "$name" >&2
                return 10
                ;;
        esac

        printf -v "$name" '%s' "$value"
        export "$name"
    done < "$file_path"

    local required_name
    for required_name in \
        HOMEBREW_BREW_GIT_REMOTE \
        HOMEBREW_CORE_GIT_REMOTE \
        HOMEBREW_API_DOMAIN \
        HOMEBREW_BOTTLE_DOMAIN; do
        if [ -z "${!required_name:-}" ]; then
            printf 'Stage 0 配置缺少变量: %s\n' "$required_name" >&2
            return 10
        fi
    done
}

# 功能：探测 Homebrew 官方 bootstrap 端点。
# 参数：无。
# 返回：0 可用，1 不可用。
probe_homebrew_official() {
    case "${POWERSHELL_SCRIPTS_BOOTSTRAP_PROBE_RESULT:-}" in
        healthy)
            return 0
            ;;
        unhealthy)
            return 1
            ;;
    esac

    command -v curl >/dev/null 2>&1 || return 1
    curl -fsSIL --max-time 5 'https://formulae.brew.sh/api/formula.json' >/dev/null 2>&1
}

# 功能：执行被 Stage 0 source 策略包装的命令。
# 参数：COMMAND 全局数组。
# 返回：被包装命令的退出码。
run_command() {
    if [ "${#COMMAND[@]}" -eq 0 ]; then
        printf '非 dry-run 模式必须在 -- 后提供 bootstrap 命令\n' >&2
        return 2
    fi

    "${COMMAND[@]}"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift 2
            ;;
        --target)
            TARGET="${2:-}"
            shift 2
            ;;
        --config)
            CONFIG_PATH="${2:-}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --output)
            OUTPUT_FORMAT="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            COMMAND=("$@")
            break
            ;;
        *)
            printf '未知参数: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

case "$MODE" in
    Direct|China|Auto)
        ;;
    *)
        printf '不支持的 mode: %s\n' "$MODE" >&2
        exit 2
        ;;
esac
case "$OUTPUT_FORMAT" in
    Text|Json)
        ;;
    *)
        printf '不支持的 output: %s\n' "$OUTPUT_FORMAT" >&2
        exit 2
        ;;
esac

if [ -z "$CONFIG_PATH" ]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    CONFIG_PATH="$SCRIPT_DIR/../../config/network/package-sources.bootstrap.env"
fi

if [ "$MODE" = 'Direct' ]; then
    emit_status 'Direct' '保持官方或现有 source' false
    if [ "$DRY_RUN" = true ]; then
        exit 0
    fi
    run_command
    exit $?
fi

if [ "$TARGET" != 'brew' ]; then
    emit_status 'Blocked' 'Stage 0 当前只安全支持 Homebrew 进程级镜像环境' false
    exit 10
fi

if [ "$MODE" = 'Auto' ] && probe_homebrew_official; then
    emit_status 'Official' '官方端点可用，不注入镜像' false
    if [ "$DRY_RUN" = true ]; then
        exit 0
    fi
    run_command
    exit $?
fi

load_brew_bootstrap_config "$CONFIG_PATH"
emit_status 'Prepared' '仅为当前 bootstrap 命令注入 Homebrew 镜像变量' true
if [ "$DRY_RUN" = true ]; then
    exit 0
fi

run_command
