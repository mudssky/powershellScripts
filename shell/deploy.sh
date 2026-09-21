#!/bin/bash

# ======================================================================
# 文件：deploy.sh
# 作用：同步 profile 与交互片段，并维护 login/interactive 受管 loader。
# 兼容性：Bash 3.2+；支持 dry-run、shell 选择、目标迁移和文件排除。
# ======================================================================
set -euo pipefail

# -- paths and defaults -------------------------------------------------
PROFILE_CONFIG_DIR="$HOME/.profile.d"
INTERACTIVE_CONFIG_DIR="$HOME/.bashrc.d"
SCRIPT_NAME=$(basename "$0")

# -- colors -------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -- options ------------------------------------------------------------
DRY_RUN=false
EXCLUDE_LIST=()
EXCLUDE_COUNT=0
SHELL_TYPE=""

# -- source directories -------------------------------------------------
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
PROFILE_DIR="$SCRIPT_DIR/profile.d"
SHARED_DIR="$SCRIPT_DIR/shared.d"
BASH_SPECIFIC_DIR="$SCRIPT_DIR/bash.d"
ZSH_SPECIFIC_DIR="$SCRIPT_DIR/zsh.d"

# -- markers ------------------------------------------------------------
LOGIN_MARKER_START='# >>> powershell-scripts login env >>>'
LOGIN_MARKER_END='# <<< powershell-scripts login env <<<'
INTERACTIVE_MARKER_START='# >>> powershell-scripts interactive env >>>'
INTERACTIVE_MARKER_END='# <<< powershell-scripts interactive env <<<'
LEGACY_INTERACTIVE_MARKER='# Load modular configuration files from ~/.bashrc.d'

# -- help ---------------------------------------------------------------
# ----------------------------------------------------------------------
# usage — 输出 deploy.sh 的命令行帮助。
#
# 参数：无。
# 输出：stdout — 选项、启动层与示例。
# 返回码：echo 的退出码。
# ----------------------------------------------------------------------
usage() {
    echo -e "${BLUE}Usage:${NC} $SCRIPT_NAME [OPTIONS]"
    echo
    echo -e "同步 ${YELLOW}shell/profile.d/${NC} 到 ${YELLOW}$PROFILE_CONFIG_DIR${NC}，供 login 与 interactive shell 共用。"
    echo -e "同步共享与 shell 专属交互片段到 ${YELLOW}$INTERACTIVE_CONFIG_DIR${NC}。"
    echo -e "维护 login profile 与 ~/.bashrc 或 ~/.zshrc 中的成对 marker loader。"
    echo
    echo -e "${BLUE}Options:${NC}"
    echo -e "  -h, --help              显示此帮助信息"
    echo -e "  -n, --dry-run           模拟目录、同步、迁移与 loader 写入，不修改文件"
    echo -e "  -s, --shell <bash|zsh>  指定目标 shell（默认自动检测）"
    echo -e "  -e, --exclude <pattern> 同时排除 profile 与交互源文件 basename（可多次）"
    echo
    echo -e "${BLUE}Examples:${NC}"
    echo -e "  $SCRIPT_NAME"
    echo -e "  $SCRIPT_NAME --dry-run --shell bash"
    echo -e "  $SCRIPT_NAME --shell zsh -e proxy.sh"
    echo
}

# -- logging ------------------------------------------------------------
# log_info — 输出信息日志。
# 参数：$1 — 日志消息。
# 返回码：echo 的退出码。
log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
# log_warn — 输出警告日志。
# 参数：$1 — 日志消息。
# 返回码：echo 的退出码。
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
# log_err — 输出错误日志。
# 参数：$1 — 日志消息。
# 返回码：echo 的退出码。
log_err() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
# log_dry — 输出 dry-run 日志。
# 参数：$1 — 日志消息。
# 返回码：echo 的退出码。
log_dry() { echo -e "${BLUE}[DRY]${NC}  $1" >&2; }

# -- shell and files ----------------------------------------------------
# ----------------------------------------------------------------------
# detect_shell — 解析目标 shell，必要时回退到 Bash。
#
# 参数：无。
# 副作用：设置 SHELL_TYPE。
# 返回码：始终返回 0。
# ----------------------------------------------------------------------
detect_shell() {
    if [ -n "$SHELL_TYPE" ]; then
        return 0
    fi
    SHELL_TYPE=$(basename "${SHELL:-}")
    if [ "$SHELL_TYPE" != 'bash' ] && [ "$SHELL_TYPE" != 'zsh' ]; then
        log_warn "无法识别默认 shell '$SHELL_TYPE'，将使用 bash 模式"
        SHELL_TYPE='bash'
    fi
}

# ensure_dir — 确保目标目录存在。
# 参数：$1 — 目录路径。
# 副作用：非 dry-run 时创建目录。
# 返回码：mkdir 或日志命令的退出码。
ensure_dir() {
    local target_dir="$1"
    if [ ! -d "$target_dir" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_dry "创建目录: $target_dir"
        else
            mkdir -p "$target_dir"
            log_info "已创建配置目录: $target_dir"
        fi
    fi
}

# backup_file — 为即将修改的非空文件创建时间戳备份。
# 参数：$1 — 文件路径。
# 副作用：非 dry-run 时创建 .bak 文件。
# 返回码：cp 或日志命令的退出码。
backup_file() {
    local target_file="$1"
    [ -s "$target_file" ] || return 0

    local timestamp backup_path
    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    backup_path="${target_file}.${timestamp}.bak"
    if [ "$DRY_RUN" = true ]; then
        log_dry "备份现有配置: $backup_path"
    else
        cp -p "$target_file" "$backup_path"
        log_info "已备份现有配置: $backup_path"
    fi
}

# is_excluded — 判断文件名是否命中排除模式。
# 参数：$1 — 文件名。
# 返回码：命中返回 0，未命中返回 1。
is_excluded() {
    local filename="$1"
    local pattern
    [ "$EXCLUDE_COUNT" -gt 0 ] || return 1
    for pattern in "${EXCLUDE_LIST[@]}"; do
        if [[ "$filename" == $pattern ]]; then
            return 0
        fi
    done
    return 1
}

# cleanup_stale_symlinks — 清理指定目录中指向不存在路径的软链接。
# 参数：$1 — 目标目录。
# 副作用：非 dry-run 时删除失效软链接。
# 返回码：成功返回 0。
cleanup_stale_symlinks() {
    local target_dir="$1"
    [ -d "$target_dir" ] || return 0

    local link target stale_count=0
    for link in "$target_dir"/*; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then
            target=$(readlink "$link")
            if [ "$DRY_RUN" = true ]; then
                log_dry "删除失效 symlink: $link -> $target"
            else
                rm "$link"
                log_info "已删除失效 symlink: $link -> $target"
            fi
            stale_count=$((stale_count + 1))
        fi
    done
    [ "$stale_count" -eq 0 ] || log_info "在 $target_dir 清理了 $stale_count 个失效 symlink。"
}

# ----------------------------------------------------------------------
# sync_dir — 将指定源目录片段同步为目标目录软链接。
# 参数：$1 — 源目录；$2 — 目标目录；$3/$4 — 源/目标扩展名。
# 输出：stdout — 已处理文件数量。
# 副作用：非 dry-run 时创建或更新软链接。
# 返回码：源目录不存在返回 1，其余成功返回 0。
sync_dir() {
    local source_dir="$1"
    local target_dir="$2"
    local source_extension="$3"
    local target_extension="$4"
    local count=0 file filename target_name target_path

    if [ ! -d "$source_dir" ]; then
        log_err "未找到源配置目录: $source_dir"
        return 1
    fi

    shopt -s nullglob
    for file in "$source_dir"/*."$source_extension"; do
        [ -f "$file" ] || continue
        filename=$(basename "$file")
        case "$filename" in
            *.example.sh|*.sample.sh)
                log_info "跳过模板: $filename"
                continue
                ;;
        esac
        if is_excluded "$filename"; then
            log_info "跳过已排除文件: $filename"
            continue
        fi

        target_name="${filename%.$source_extension}.$target_extension"
        target_path="$target_dir/$target_name"

        if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$file" ]; then
            log_info "软链接已是目标内容: $target_path"
        elif [ "$DRY_RUN" = true ]; then
            log_dry "创建软链接: $target_path -> $file"
        else
            ln -sf "$file" "$target_path"
            log_info "已创建软链接: $target_path -> $file"
        fi
        count=$((count + 1))
    done
    shopt -u nullglob
    echo "$count"
}

# -- managed blocks -----------------------------------------------------
# render_profile_loader — 输出 login profile 受管块。
# 参数：无。
# 输出：stdout — 完整 marker block。
# 返回码：cat 的退出码。
render_profile_loader() {
    cat <<'EOF'
# >>> powershell-scripts login env >>>
# login 与 interactive shell 共用的基础环境，按文件名顺序加载。
for _ps_config in "$HOME/.profile.d/"*.sh; do
    [ -r "$_ps_config" ] && . "$_ps_config"
done
unset _ps_config
# <<< powershell-scripts login env <<<
EOF
}

# render_interactive_loader — 输出 rc 受管块。
# 参数：无。
# 输出：stdout — 完整 marker block。
# 返回码：cat 的退出码。
render_interactive_loader() {
    cat <<'EOF'
# >>> powershell-scripts interactive env >>>
# 非 login 的交互 shell 也需要恢复共用基础环境。
for _ps_config in "$HOME/.profile.d/"*.sh; do
    [ -r "$_ps_config" ] && . "$_ps_config"
done
unset _ps_config

# alias、函数、补全和 prompt 只进入交互 shell。
case "$-" in
    *i*)
        for _ps_config in "$HOME/.bashrc.d/"*.sh; do
            [ -r "$_ps_config" ] && . "$_ps_config"
        done
        unset _ps_config
        ;;
esac
# <<< powershell-scripts interactive env <<<
EOF
}

# ----------------------------------------------------------------------
# build_managed_file — 生成替换受管块后的完整文件，并兼容旧 rc loader。
#
# 参数：
#   $1 — 原文件；$2/$3 — start/end marker；$4 — 新受管块；
#   $5 — 可选 legacy 单行 marker；$6 — 输出文件。
# 返回码：透传 awk 退出码。
# ----------------------------------------------------------------------
build_managed_file() {
    local target_file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local managed_block="$4"
    local legacy_marker="$5"
    local output_file="$6"

    POWERSHELL_SCRIPTS_BLOCK="$managed_block" \
    POWERSHELL_SCRIPTS_START="$start_marker" \
    POWERSHELL_SCRIPTS_END="$end_marker" \
    POWERSHELL_SCRIPTS_LEGACY="$legacy_marker" \
    awk '
        function emit_block() {
            if (!replaced) {
                printf "%s\n", ENVIRON["POWERSHELL_SCRIPTS_BLOCK"]
                replaced = 1
                printed = 1
            }
        }
        $0 == ENVIRON["POWERSHELL_SCRIPTS_START"] {
            emit_block()
            in_block = 1
            next
        }
        in_block && $0 == ENVIRON["POWERSHELL_SCRIPTS_END"] {
            in_block = 0
            next
        }
        in_block { next }
        ENVIRON["POWERSHELL_SCRIPTS_LEGACY"] != "" && $0 == ENVIRON["POWERSHELL_SCRIPTS_LEGACY"] {
            emit_block()
            legacy_pending = 1
            next
        }
        legacy_pending {
            legacy_pending = 0
            if ($0 == "if [ -d \"$HOME/.bashrc.d\" ]; then") {
                in_legacy = 1
                legacy_depth = 1
                next
            }
            print
            printed = 1
            next
        }
        in_legacy {
            if ($0 ~ /^[[:space:]]*if[[:space:]].*;[[:space:]]*then[[:space:]]*$/) {
                legacy_depth++
            }
            if ($0 ~ /^[[:space:]]*fi[[:space:]]*$/) {
                legacy_depth--
                if (legacy_depth <= 0) in_legacy = 0
            }
            next
        }
        { print; printed = 1 }
        END {
            if (!replaced) {
                if (printed) printf "\n"
                emit_block()
            }
        }
    ' "$target_file" > "$output_file"
}

# build_file_without_managed_block — 生成删除指定受管块后的完整文件。
# 参数：$1 — 原文件；$2/$3 — start/end marker；$4 — 输出文件。
# 返回码：透传 awk 退出码。
build_file_without_managed_block() {
    local target_file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local output_file="$4"

    POWERSHELL_SCRIPTS_START="$start_marker" \
    POWERSHELL_SCRIPTS_END="$end_marker" \
    awk '
        $0 == ENVIRON["POWERSHELL_SCRIPTS_START"] { in_block = 1; next }
        in_block && $0 == ENVIRON["POWERSHELL_SCRIPTS_END"] { in_block = 0; next }
        in_block { next }
        { print }
    ' "$target_file" > "$output_file"
}

# ----------------------------------------------------------------------
# apply_rewritten_file — 比较并提交已生成的完整文件。
#
# 参数：$1 — 目标文件；$2 — 临时文件；$3 — 变更描述。
# 副作用：内容变化时备份并改写目标；始终删除临时文件。
# 返回码：成功返回 0；备份或写入失败时返回非 0。
# ----------------------------------------------------------------------
apply_rewritten_file() {
    local target_file="$1"
    local desired_file="$2"
    local change_description="$3"

    if cmp -s "$desired_file" "$target_file"; then
        rm -f "$desired_file"
        log_info "$target_file 已是最新。"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log_dry "$change_description"
        [ ! -s "$target_file" ] || backup_file "$target_file"
        rm -f "$desired_file"
        return 0
    fi

    if ! backup_file "$target_file"; then
        rm -f "$desired_file"
        return 1
    fi
    if ! cat "$desired_file" > "$target_file"; then
        rm -f "$desired_file"
        return 1
    fi
    rm -f "$desired_file"
    log_info "已${change_description}。"
}

# ----------------------------------------------------------------------
# update_managed_block — 写入或替换通用 marker block，并迁移 legacy rc loader。
#
# 参数：
#   $1 — 目标文件；$2/$3 — start/end marker；$4 — 完整受管块；
#   $5 — 文件不存在时是否创建；$6 — 可选 legacy 单行 marker。
# 副作用：内容变化时备份并改写目标文件；dry-run 只记录动作。
# 返回码：成功返回 0；文件操作失败时返回非 0。
# ----------------------------------------------------------------------
update_managed_block() {
    local target_file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local managed_block="$4"
    local create_if_missing="$5"
    local legacy_marker="${6:-}"
    local action='写入'
    local desired_file

    if [ ! -f "$target_file" ] && [ "$create_if_missing" != true ]; then
        return 0
    fi
    if [ -f "$target_file" ] && grep -Fq "$start_marker" "$target_file"; then
        action='替换'
    elif [ -n "$legacy_marker" ] && [ -f "$target_file" ] && grep -Fq "$legacy_marker" "$target_file"; then
        action='迁移'
    fi

    if [ ! -f "$target_file" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_dry "创建 $target_file 并写入受管块"
        else
            printf '%s\n' "$managed_block" > "$target_file"
            log_info "已创建 $target_file 并写入受管块。"
        fi
        return 0
    fi

    desired_file=$(mktemp "${TMPDIR:-/tmp}/powershell-scripts-loader.XXXXXX") || return 1
    if ! build_managed_file "$target_file" "$start_marker" "$end_marker" "$managed_block" "$legacy_marker" "$desired_file"; then
        rm -f "$desired_file"
        return 1
    fi
    apply_rewritten_file "$target_file" "$desired_file" "$action $target_file 中的受管块"
}

# remove_managed_block — 从非活动文件删除精确 marker block。
# 参数：$1 — 文件；$2/$3 — start/end marker。
# 返回码：成功返回 0；文件操作失败时返回非 0。
remove_managed_block() {
    local target_file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local desired_file

    [ -f "$target_file" ] || return 0
    grep -Fq "$start_marker" "$target_file" || return 0

    desired_file=$(mktemp "${TMPDIR:-/tmp}/powershell-scripts-loader.XXXXXX") || return 1
    if ! build_file_without_managed_block "$target_file" "$start_marker" "$end_marker" "$desired_file"; then
        rm -f "$desired_file"
        return 1
    fi
    apply_rewritten_file "$target_file" "$desired_file" "从非活动 profile 清理 $target_file 中的受管块"
}

# select_login_profile — 选择实际生效的 login profile。
# 参数：无。
# 输出：stdout — 目标 profile 路径。
# 返回码：始终返回 0。
select_login_profile() {
    if [ "$SHELL_TYPE" = 'zsh' ]; then
        printf '%s\n' "$HOME/.zprofile"
        return 0
    fi

    local candidate
    for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    printf '%s\n' "$HOME/.profile"
}

# ensure_login_loader — 更新有效 login target，并清理 Bash 非活动候选。
# 参数：无。
# 副作用：更新 login profile。
# 返回码：成功返回 0。
ensure_login_loader() {
    local target block candidate
    target=$(select_login_profile)
    block=$(render_profile_loader)
    log_info "有效 login profile: $target"
    update_managed_block "$target" "$LOGIN_MARKER_START" "$LOGIN_MARKER_END" "$block" true

    if [ "$SHELL_TYPE" = 'bash' ]; then
        for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
            [ "$candidate" = "$target" ] || remove_managed_block "$candidate" "$LOGIN_MARKER_START" "$LOGIN_MARKER_END"
        done
    fi
}

# ensure_interactive_loader — 更新目标 rc，并迁移 legacy 单行 loader。
# 参数：无。
# 副作用：更新目标 rc 文件。
# 返回码：成功返回 0。
ensure_interactive_loader() {
    local rc_file block
    if [ "$SHELL_TYPE" = 'zsh' ]; then
        rc_file="$HOME/.zshrc"
    else
        rc_file="$HOME/.bashrc"
    fi
    block=$(render_interactive_loader)
    update_managed_block "$rc_file" "$INTERACTIVE_MARKER_START" "$INTERACTIVE_MARKER_END" "$block" true "$LEGACY_INTERACTIVE_MARKER"
}

# -- synchronization ----------------------------------------------------
# sync_snippets — 同步基础环境与目标 shell 交互片段。
# 参数：无。
# 副作用：创建或更新两个目标目录中的软链接。
# 返回码：任一源目录同步失败时返回非 0。
sync_snippets() {
    local profile_count shared_count specific_count total
    log_info "同步 profile.d/ 基础环境片段..."
    profile_count=$(sync_dir "$PROFILE_DIR" "$PROFILE_CONFIG_DIR" 'sh' 'sh')

    log_info "同步 shared.d/ 交互片段..."
    shared_count=$(sync_dir "$SHARED_DIR" "$INTERACTIVE_CONFIG_DIR" 'sh' 'sh')
    specific_count=0
    if [ "$SHELL_TYPE" = 'zsh' ]; then
        log_info "同步 zsh.d/ 专属交互片段..."
        specific_count=$(sync_dir "$ZSH_SPECIFIC_DIR" "$INTERACTIVE_CONFIG_DIR" 'zsh' 'sh')
    else
        log_info "同步 bash.d/ 专属交互片段..."
        specific_count=$(sync_dir "$BASH_SPECIFIC_DIR" "$INTERACTIVE_CONFIG_DIR" 'sh' 'sh')
    fi

    total=$((profile_count + shared_count + specific_count))
    log_info "同步完成，共处理 $total 个片段。"
}

# -- main ---------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--shell)
            if [[ ${2:-} != '' && ${2:-} != -* ]]; then
                SHELL_TYPE="$2"
                if [ "$SHELL_TYPE" != 'bash' ] && [ "$SHELL_TYPE" != 'zsh' ]; then
                    log_err '--shell 参数仅支持 bash 或 zsh'
                    exit 2
                fi
                shift 2
            else
                log_err '参数 --shell 需要一个值（bash 或 zsh）'
                exit 2
            fi
            ;;
        -e|--exclude)
            if [[ ${2:-} != '' && ${2:-} != -* ]]; then
                EXCLUDE_LIST+=("$2")
                EXCLUDE_COUNT=$((EXCLUDE_COUNT + 1))
                shift 2
            else
                log_err '参数 --exclude 需要一个模式值'
                exit 2
            fi
            ;;
        *)
            log_err "未知参数: $1"
            usage
            exit 2
            ;;
    esac
done

detect_shell
log_info "目标 shell: $SHELL_TYPE"
[ "$EXCLUDE_COUNT" -eq 0 ] || log_info "排除列表: ${EXCLUDE_LIST[*]}"

ensure_dir "$PROFILE_CONFIG_DIR"
ensure_dir "$INTERACTIVE_CONFIG_DIR"
cleanup_stale_symlinks "$PROFILE_CONFIG_DIR"
cleanup_stale_symlinks "$INTERACTIVE_CONFIG_DIR"
sync_snippets
ensure_login_loader
ensure_interactive_loader
