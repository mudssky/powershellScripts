#!/usr/bin/env bash

# aliyun-oss-put.sh
# 使用 OSS PutObject + V4 签名上传单个本地文件到阿里云 OSS。
#
# 支持的输入来源：
# - CLI 参数：提供本地文件路径与目标对象信息。
# - 环境变量：提供凭证与可复用的默认配置。
# - 当前工作目录下的 .env.aliyun-oss-put / .env.aliyun-oss-put.local。
#
# 配置优先级：
# 1. 当前 shell 中已存在的环境变量
# 2. .env.aliyun-oss-put.local
# 3. .env.aliyun-oss-put
#
# 退出码：
# 0  成功
# 1  用法错误或本地校验失败
# 2  依赖缺失
# 3  网络 / curl 失败
# 4  OSS API 返回失败

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
FILE_PATH=""
BUCKET_NAME=""
OBJECT_KEY=""
REGION_ID=""
HOST_INPUT=""
CONTENT_TYPE=""
OVERWRITE_MODE="false"
VERBOSE_MODE="false"
DEBUG_SIGNING_MODE="false"

REQUEST_HOST=""
REQUEST_URL=""
CANONICAL_URI=""
RFC_1123_DATE=""
ISO_8601_DATE=""
SHORT_DATE=""
FILE_SIZE=""
FILE_MD5_BASE64=""
CONTENT_SHA256="UNSIGNED-PAYLOAD"
FILE_SHA256_HEX=""

TMP_DIR=""
RESPONSE_HEADERS_FILE=""
RESPONSE_BODY_FILE=""
INITIAL_ENV_VARS=""

# 仅在 verbose 模式下输出简洁日志，避免默认输出干扰脚本结果。
log_verbose() {
    if [ "$VERBOSE_MODE" = "true" ]; then
        printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2
    fi
}

# 输出致命错误并按指定退出码退出。
die() {
    local exit_code="$1"
    shift
    printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2
    exit "$exit_code"
}

# 输出命令用法以及支持的配置来源说明。
show_help() {
    cat <<'EOF'
Usage:
  aliyun-oss-put.sh --file <path> --bucket <bucket> --key <object-key> --region <region> --host <host> [options]

Required flags:
  --file <path>             Local file to upload.
  --bucket <bucket>         OSS bucket name.
  --key <object-key>        Target OSS object key, including remote path and file name.
  --region <region>         OSS region id such as cn-hangzhou.
  --host <host>             Actual request host or standard OSS endpoint.

Optional flags:
  --content-type <type>     Content-Type header. Default: application/octet-stream.
  --overwrite               Allow overwriting an existing object.
  --verbose                 Print extra execution details.
  --debug-signing           Print canonical request and string-to-sign with secrets masked.
  --help                    Show this help message.

Environment variables:
  ALIYUN_ACCESS_KEY_ID
  ALIYUN_ACCESS_KEY_SECRET
  ALIYUN_SECURITY_TOKEN     Optional STS token.
  ALIYUN_OSS_BUCKET         Optional default for --bucket.
  ALIYUN_OSS_REGION         Optional default for --region.
  ALIYUN_OSS_HOST           Optional default for --host.
  ALIYUN_OSS_CONTENT_TYPE   Optional default for --content-type.

Dotenv loading:
  The script reads .env.aliyun-oss-put first and then .env.aliyun-oss-put.local from the current working directory.
  Existing shell environment variables always win over file-based values.

Examples:
  export ALIYUN_ACCESS_KEY_ID='your-ak'
  export ALIYUN_ACCESS_KEY_SECRET='your-sk'
  ./scripts/bash/aliyun-oss-put.sh \
    --file ./demo.txt \
    --bucket examplebucket \
    --key demo/demo.txt \
    --region cn-hangzhou \
    --host examplebucket.oss-cn-hangzhou.aliyuncs.com

  ./scripts/bash/aliyun-oss-put.sh \
    --file ./demo.txt \
    --bucket examplebucket \
    --key demo/demo.txt \
    --region cn-hangzhou \
    --host static.example.com \
    --overwrite
EOF
}

# 去除字符串首尾空白字符，统一后续解析行为。
trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# 判断变量是否在 dotenv 加载前就已经存在于 shell 环境中。
env_var_preexisted() {
    local var_name="$1"
    case "
$INITIAL_ENV_VARS
" in
        *"
$var_name
"*) return 0 ;;
        *) return 1 ;;
    esac
}

# 以保守方式解析 dotenv 值，避免执行任何 shell 代码。
normalize_dotenv_value() {
    local raw_value="$1"
    local normalized_value

    normalized_value="$(trim_whitespace "$raw_value")"
    if [ -z "$normalized_value" ]; then
        printf '%s' ""
        return 0
    fi

    case "$normalized_value" in
        \"*\")
            normalized_value="${normalized_value#\"}"
            normalized_value="${normalized_value%\"}"
            ;;
        \'*\')
            normalized_value="${normalized_value#\'}"
            normalized_value="${normalized_value%\'}"
            ;;
        *)
            normalized_value="${normalized_value%%[[:space:]]\#*}"
            normalized_value="$(trim_whitespace "$normalized_value")"
            ;;
    esac

    printf '%s' "$normalized_value"
}

# 从 dotenv 文件读取 KEY=VALUE。
# 设计意图：
# - 保留用户在脚本启动前已 export 的环境变量最高优先级。
# - 允许后加载的 .local 覆盖先加载的共享配置文件。
load_env_file_if_present() {
    local env_file_path="$1"
    local line_number=0
    local line
    local payload
    local key_name
    local raw_value
    local normalized_value

    if [ ! -f "$env_file_path" ]; then
        return 0
    fi

    log_verbose "Loading dotenv file: $env_file_path"

    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))
        line="$(trim_whitespace "$line")"

        if [ -z "$line" ]; then
            continue
        fi

        case "$line" in
            \#*) continue ;;
        esac

        payload="$line"
        case "$payload" in
            export[[:space:]]*)
                payload="${payload#export}"
                payload="$(trim_whitespace "$payload")"
                ;;
        esac

        if [[ "$payload" != *=* ]]; then
            printf '[%s] ignoring invalid dotenv line %s in %s\n' "$SCRIPT_NAME" "$line_number" "$env_file_path" >&2
            continue
        fi

        key_name="${payload%%=*}"
        raw_value="${payload#*=}"
        key_name="$(trim_whitespace "$key_name")"

        if [[ ! "$key_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            printf '[%s] ignoring invalid dotenv key "%s" in %s:%s\n' "$SCRIPT_NAME" "$key_name" "$env_file_path" "$line_number" >&2
            continue
        fi

        if env_var_preexisted "$key_name"; then
            continue
        fi

        normalized_value="$(normalize_dotenv_value "$raw_value")"
        export "$key_name=$normalized_value"
    done < "$env_file_path"
}

# 读取脚本专属 dotenv 文件，避免与同目录其他脚本共用通用 .env 时发生冲突。
# 先读共享配置，再读 .local，本地文件因此拥有更高优先级。
load_dotenv_files() {
    local work_dir="$PWD"
    INITIAL_ENV_VARS="$(env | LC_ALL=C cut -d= -f1)"
    load_env_file_if_present "$work_dir/.env.aliyun-oss-put"
    load_env_file_if_present "$work_dir/.env.aliyun-oss-put.local"
}

# 解析 CLI 参数，命令行显式传值始终高于环境变量默认值。
parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --file)
                [ "$#" -ge 2 ] || die 1 "missing value for --file"
                FILE_PATH="$2"
                shift 2
                ;;
            --bucket)
                [ "$#" -ge 2 ] || die 1 "missing value for --bucket"
                BUCKET_NAME="$2"
                shift 2
                ;;
            --key)
                [ "$#" -ge 2 ] || die 1 "missing value for --key"
                OBJECT_KEY="$2"
                shift 2
                ;;
            --region)
                [ "$#" -ge 2 ] || die 1 "missing value for --region"
                REGION_ID="$2"
                shift 2
                ;;
            --host)
                [ "$#" -ge 2 ] || die 1 "missing value for --host"
                HOST_INPUT="$2"
                shift 2
                ;;
            --content-type)
                [ "$#" -ge 2 ] || die 1 "missing value for --content-type"
                CONTENT_TYPE="$2"
                shift 2
                ;;
            --overwrite)
                OVERWRITE_MODE="true"
                shift
                ;;
            --verbose)
                VERBOSE_MODE="true"
                shift
                ;;
            --debug-signing)
                DEBUG_SIGNING_MODE="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                die 1 "unknown argument: $1"
                ;;
        esac
    done
}

# 在 dotenv 加载完成后，用环境变量补齐未显式传入的可选参数。
apply_environment_defaults() {
    if [ -z "$BUCKET_NAME" ] && [ -n "${ALIYUN_OSS_BUCKET:-}" ]; then
        BUCKET_NAME="$ALIYUN_OSS_BUCKET"
    fi

    if [ -z "$REGION_ID" ] && [ -n "${ALIYUN_OSS_REGION:-}" ]; then
        REGION_ID="$ALIYUN_OSS_REGION"
    fi

    if [ -z "$HOST_INPUT" ] && [ -n "${ALIYUN_OSS_HOST:-}" ]; then
        HOST_INPUT="$ALIYUN_OSS_HOST"
    fi

    if [ -z "$CONTENT_TYPE" ] && [ -n "${ALIYUN_OSS_CONTENT_TYPE:-}" ]; then
        CONTENT_TYPE="$ALIYUN_OSS_CONTENT_TYPE"
    fi
}

# 规范化 region 与 host，生成实际请求使用的目标 host。
normalize_target() {
    local normalized_host

    REGION_ID="${REGION_ID#oss-}"
    HOST_INPUT="$(trim_whitespace "$HOST_INPUT")"
    HOST_INPUT="${HOST_INPUT#https://}"
    HOST_INPUT="${HOST_INPUT#http://}"
    HOST_INPUT="${HOST_INPUT%/}"

    normalized_host="$HOST_INPUT"

    # 标准 OSS endpoint 既可能传服务域名，也可能直接传 bucket 域名；这里统一补齐。
    if [[ "$normalized_host" == oss-*.aliyuncs.com ]] || [[ "$normalized_host" == oss-*.aliyuncs.com.cn ]]; then
        normalized_host="${BUCKET_NAME}.${normalized_host}"
    fi

    REQUEST_HOST="$normalized_host"
}

# 校验必填参数、凭证来源与基础输入格式，尽量在发请求前失败。
validate_inputs() {
    [ -n "$FILE_PATH" ] || die 1 "--file is required"
    [ -n "$BUCKET_NAME" ] || die 1 "--bucket is required or set ALIYUN_OSS_BUCKET"
    [ -n "$OBJECT_KEY" ] || die 1 "--key is required"
    [ -n "$REGION_ID" ] || die 1 "--region is required or set ALIYUN_OSS_REGION"
    [ -n "$HOST_INPUT" ] || die 1 "--host is required or set ALIYUN_OSS_HOST"
    [ -n "${ALIYUN_ACCESS_KEY_ID:-}" ] || die 1 "ALIYUN_ACCESS_KEY_ID is required"
    [ -n "${ALIYUN_ACCESS_KEY_SECRET:-}" ] || die 1 "ALIYUN_ACCESS_KEY_SECRET is required"

    [ -f "$FILE_PATH" ] || die 1 "local file does not exist: $FILE_PATH"
    [ -r "$FILE_PATH" ] || die 1 "local file is not readable: $FILE_PATH"

    OBJECT_KEY="${OBJECT_KEY#/}"
    [ -n "$OBJECT_KEY" ] || die 1 "--key must not be empty after trimming the leading slash"

    normalize_target

    [ -n "$REQUEST_HOST" ] || die 1 "host normalization produced an empty host"
    [[ "$REQUEST_HOST" != */* ]] || die 1 "--host must not contain a path segment"

    if [ -z "$CONTENT_TYPE" ]; then
        CONTENT_TYPE="application/octet-stream"
    fi
}

# 构造请求前先确认运行时依赖完整，避免中途失败。
check_dependencies() {
    command -v bash >/dev/null 2>&1 || die 2 "bash is required"
    command -v curl >/dev/null 2>&1 || die 2 "curl is required"
    command -v openssl >/dev/null 2>&1 || die 2 "openssl is required"
    command -v od >/dev/null 2>&1 || die 2 "od is required"
    command -v tr >/dev/null 2>&1 || die 2 "tr is required"
    command -v awk >/dev/null 2>&1 || die 2 "awk is required"
    command -v cut >/dev/null 2>&1 || die 2 "cut is required"
    command -v sed >/dev/null 2>&1 || die 2 "sed is required"
    command -v date >/dev/null 2>&1 || die 2 "date is required"
    command -v wc >/dev/null 2>&1 || die 2 "wc is required"
}

# 对对象 key 做百分号编码，同时保留 '/' 分隔符语义。
percent_encode_preserving_slash() {
    local LC_ALL=C
    local raw_input="$1"
    local encoded_output=""
    local byte_index=0
    local raw_length
    local byte_char
    local hex_value

    raw_length=${#raw_input}

    while [ "$byte_index" -lt "$raw_length" ]; do
        byte_char="${raw_input:$byte_index:1}"
        case "$byte_char" in
            [a-zA-Z0-9.~_-]|/)
                encoded_output="${encoded_output}${byte_char}"
                ;;
            *)
                hex_value="$(printf '%s' "$byte_char" | od -An -tx1 -v | tr -d ' \n' | tr '[:lower:]' '[:upper:]')"
                encoded_output="${encoded_output}%${hex_value}"
                ;;
        esac
        byte_index=$((byte_index + 1))
    done

    printf '%s' "$encoded_output"
}

# 将 openssl 的二进制输出转换为小写十六进制字符串。
binary_to_hex() {
    od -An -tx1 -v | tr -d ' \n'
}

# 计算文本内容的 SHA256 十六进制摘要。
sha256_hex_of_text() {
    printf '%s' "$1" | openssl dgst -sha256 -binary | binary_to_hex
}

# 使用原始字符串 key 计算 HMAC-SHA256 十六进制摘要。
hmac_sha256_hex_with_raw_key() {
    local raw_key="$1"
    local message="$2"
    printf '%s' "$message" | openssl dgst -sha256 -mac HMAC -macopt "key:${raw_key}" -binary | binary_to_hex
}

# 使用十六进制编码 key 计算 HMAC-SHA256 十六进制摘要。
hmac_sha256_hex_with_hex_key() {
    local hex_key="$1"
    local message="$2"
    printf '%s' "$message" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${hex_key}" -binary | binary_to_hex
}

# 生成请求所需时间戳与内容完整性相关字段。
# 这里额外计算本地文件 SHA256，仅用于排查问题，不参与当前请求签名。
prepare_request_values() {
    local encoded_object_key

    ISO_8601_DATE="$(LC_ALL=C date -u '+%Y%m%dT%H%M%SZ')"
    SHORT_DATE="${ISO_8601_DATE%%T*}"
    RFC_1123_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')"
    FILE_SIZE="$(wc -c < "$FILE_PATH" | awk '{print $1}')"
    FILE_MD5_BASE64="$(openssl dgst -md5 -binary "$FILE_PATH" | openssl enc -base64 -A)"
    FILE_SHA256_HEX="$(openssl dgst -sha256 -binary "$FILE_PATH" | binary_to_hex)"

    encoded_object_key="$(percent_encode_preserving_slash "$OBJECT_KEY")"
    REQUEST_URL="https://${REQUEST_HOST}/${encoded_object_key}"
    CANONICAL_URI="/${BUCKET_NAME}/${encoded_object_key}"
}

# 构造 OSS V4 签名要求的 canonical headers 列表。
build_canonical_headers() {
    local canonical_headers=""

    append_canonical_header() {
        local header_name="$1"
        local header_value="$2"

        if [ -n "$canonical_headers" ]; then
            canonical_headers="${canonical_headers}"$'\n'
        fi

        canonical_headers="${canonical_headers}${header_name}:${header_value}"
    }

    append_canonical_header "content-md5" "$FILE_MD5_BASE64"
    append_canonical_header "content-type" "$CONTENT_TYPE"

    if [ "$OVERWRITE_MODE" != "true" ]; then
        append_canonical_header "x-oss-forbid-overwrite" "true"
    fi

    append_canonical_header "x-oss-content-sha256" "$CONTENT_SHA256"
    append_canonical_header "x-oss-date" "$ISO_8601_DATE"

    if [ -n "${ALIYUN_SECURITY_TOKEN:-}" ]; then
        append_canonical_header "x-oss-security-token" "${ALIYUN_SECURITY_TOKEN}"
    fi

    printf '%s' "$canonical_headers"
}

# 按 OSS V4 规则构造 canonical request。
build_canonical_request() {
    local canonical_headers

    canonical_headers="$(build_canonical_headers)"

    printf 'PUT\n%s\n\n%s\n\n%s' \
        "$CANONICAL_URI" \
        "$canonical_headers" \
        "$CONTENT_SHA256"
}

# 基于 canonical request 摘要构造 string-to-sign。
build_string_to_sign() {
    local canonical_request="$1"
    local scope
    local canonical_hash

    scope="${SHORT_DATE}/${REGION_ID}/oss/aliyun_v4_request"
    canonical_hash="$(sha256_hex_of_text "$canonical_request")"

    printf 'OSS4-HMAC-SHA256\n%s\n%s\n%s' \
        "$ISO_8601_DATE" \
        "$scope" \
        "$canonical_hash"
}

# 按照官方定义的派生链路计算最终 OSS V4 签名。
build_signature() {
    local string_to_sign="$1"
    local k_date
    local k_region
    local k_service
    local k_signing

    k_date="$(hmac_sha256_hex_with_raw_key "aliyun_v4${ALIYUN_ACCESS_KEY_SECRET}" "$SHORT_DATE")"
    k_region="$(hmac_sha256_hex_with_hex_key "$k_date" "$REGION_ID")"
    k_service="$(hmac_sha256_hex_with_hex_key "$k_region" "oss")"
    k_signing="$(hmac_sha256_hex_with_hex_key "$k_service" "aliyun_v4_request")"

    hmac_sha256_hex_with_hex_key "$k_signing" "$string_to_sign"
}

# 输出签名调试材料，同时避免泄露密钥本身。
print_debug_signing() {
    local canonical_request="$1"
    local string_to_sign="$2"
    local signature="$3"
    local credential_scope="${SHORT_DATE}/${REGION_ID}/oss/aliyun_v4_request"

    if [ "$DEBUG_SIGNING_MODE" != "true" ]; then
        return 0
    fi

    cat >&2 <<EOF
[${SCRIPT_NAME}] Canonical request:
${canonical_request}

[${SCRIPT_NAME}] String to sign:
${string_to_sign}

[${SCRIPT_NAME}] Credential scope:
${ALIYUN_ACCESS_KEY_ID}/${credential_scope}

[${SCRIPT_NAME}] Signature:
${signature}
EOF
}

# 创建响应头与响应体临时文件，供成功和失败场景统一解析。
prepare_temp_files() {
    TMP_DIR="$(mktemp -d)"
    RESPONSE_HEADERS_FILE="${TMP_DIR}/response.headers"
    RESPONSE_BODY_FILE="${TMP_DIR}/response.body"
}

# 无论成功失败，退出时都清理临时目录。
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

# 从已捕获的响应头中按大小写不敏感方式读取指定 header。
read_response_header() {
    local header_name="$1"
    awk -v target_header="$(printf '%s' "$header_name" | tr '[:upper:]' '[:lower:]')" '
        {
            gsub(/\r$/, "", $0)
            line = $0
            lower = tolower(line)
            prefix = target_header ":"
            if (index(lower, prefix) == 1) {
                value = substr(line, length(prefix) + 1)
                sub(/^[[:space:]]+/, "", value)
                print value
                exit
            }
        }
    ' "$RESPONSE_HEADERS_FILE"
}

# 从 OSS XML 错误响应中提取简单标签值。
xml_tag_value() {
    local tag_name="$1"
    tr -d '\r\n' < "$RESPONSE_BODY_FILE" | sed -n "s:.*<${tag_name}>\\([^<]*\\)</${tag_name}>.*:\\1:p"
}

# 在真正上传前打印本地文件关键信息，便于比对“上传的是不是预期文件”。
print_pre_upload_diagnostics() {
    printf '[%s] local-file: %s\n' "$SCRIPT_NAME" "$FILE_PATH" >&2
    printf '[%s] object-key: %s\n' "$SCRIPT_NAME" "$OBJECT_KEY" >&2
    printf '[%s] file-size: %s\n' "$SCRIPT_NAME" "$FILE_SIZE" >&2
    printf '[%s] sha256: %s\n' "$SCRIPT_NAME" "$FILE_SHA256_HEX" >&2
}

# 执行 PUT 上传，并同时保留响应头和响应体用于成功/失败处理。
perform_upload() {
    local canonical_request
    local string_to_sign
    local signature
    local authorization_header
    local -a curl_args
    local http_status
    local curl_exit_code
    local request_id
    local etag
    local version_id
    local error_code
    local error_message

    canonical_request="$(build_canonical_request)"
    string_to_sign="$(build_string_to_sign "$canonical_request")"
    signature="$(build_signature "$string_to_sign")"

    authorization_header="OSS4-HMAC-SHA256 Credential=${ALIYUN_ACCESS_KEY_ID}/${SHORT_DATE}/${REGION_ID}/oss/aliyun_v4_request,Signature=${signature}"

    print_debug_signing "$canonical_request" "$string_to_sign" "$signature"
    log_verbose "Request URL: $REQUEST_URL"
    log_verbose "Request host: $REQUEST_HOST"

    curl_args=(
        -sS
        --request PUT
        --upload-file "$FILE_PATH"
        --header "Authorization: ${authorization_header}"
        --header "Content-Length: ${FILE_SIZE}"
        --header "Content-MD5: ${FILE_MD5_BASE64}"
        --header "Content-Type: ${CONTENT_TYPE}"
        --header "Date: ${RFC_1123_DATE}"
        --header "x-oss-content-sha256: ${CONTENT_SHA256}"
        --header "x-oss-date: ${ISO_8601_DATE}"
        --dump-header "$RESPONSE_HEADERS_FILE"
        --output "$RESPONSE_BODY_FILE"
        --write-out '%{http_code}'
    )

    if [ -n "${ALIYUN_SECURITY_TOKEN:-}" ]; then
        curl_args+=(
            --header "x-oss-security-token: ${ALIYUN_SECURITY_TOKEN}"
        )
    fi

    if [ "$OVERWRITE_MODE" != "true" ]; then
        curl_args+=(
            --header "x-oss-forbid-overwrite: true"
        )
    fi

    curl_args+=("$REQUEST_URL")

    set +e
    http_status="$(curl "${curl_args[@]}")"
    curl_exit_code=$?
    set -e

    if [ "$curl_exit_code" -ne 0 ]; then
        die 3 "curl request failed with exit code ${curl_exit_code}"
    fi

    request_id="$(read_response_header 'x-oss-request-id')"

    if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
        etag="$(read_response_header 'ETag')"
        version_id="$(read_response_header 'x-oss-version-id')"

        printf 'Upload succeeded.\n'
        printf 'bucket: %s\n' "$BUCKET_NAME"
        printf 'key: %s\n' "$OBJECT_KEY"
        printf 'host: %s\n' "$REQUEST_HOST"
        printf 'etag: %s\n' "${etag:-n/a}"
        printf 'request-id: %s\n' "${request_id:-n/a}"

        if [ -n "$version_id" ]; then
            printf 'version-id: %s\n' "$version_id"
        fi

        return 0
    fi

    error_code="$(xml_tag_value 'Code')"
    error_message="$(xml_tag_value 'Message')"

    printf 'Upload failed.\n' >&2
    printf 'http-status: %s\n' "$http_status" >&2
    printf 'request-id: %s\n' "${request_id:-n/a}" >&2

    if [ -n "$error_code" ]; then
        printf 'oss-code: %s\n' "$error_code" >&2
    fi

    if [ -n "$error_message" ]; then
        printf 'oss-message: %s\n' "$error_message" >&2
    fi

    if [ "$OVERWRITE_MODE" != "true" ] && { [[ "$http_status" == "409" ]] || [[ "$http_status" == "412" ]] || [[ "$error_code" == "FileAlreadyExists" ]] || [[ "$error_code" == "ObjectAlreadyExists" ]]; }; then
        printf 'hint: rerun with --overwrite if replacing the existing object is intentional.\n' >&2
    fi

    if [[ "$http_status" == "403" ]]; then
        printf 'hint: verify host, region, credentials, and custom-domain policy for the target bucket.\n' >&2
    fi

    exit 4
}

main() {
    trap cleanup EXIT
    parse_arguments "$@"
    load_dotenv_files
    apply_environment_defaults
    validate_inputs
    check_dependencies
    prepare_temp_files
    prepare_request_values
    print_pre_upload_diagnostics
    perform_upload
}

main "$@"
