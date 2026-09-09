#!/bin/bash

# ======================================================================
# 文件：deploy.sh
# 作用：同步 shared.d 与 shell 专属片段，确保 bashrc/zshrc 加载器存在，
#       并维护登录 profile 中的 brew/fnm 受管环境块。
# 兼容性：Bash；支持 dry-run、shell 选择和文件排除。
# ======================================================================
set -euo pipefail

# -- paths and defaults -------------------------------------------------
CONFIG_DIR="$HOME/.bashrc.d"
SCRIPT_NAME=$(basename "$0")

# -- colors -------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -- options ------------------------------------------------------------
DRY_RUN=false
EXCLUDE_LIST=()
EXCLUDE_COUNT=0
SHELL_TYPE=""

# -- source directories -------------------------------------------------
# 解析脚本真实路径，兼容通过软链接调用。
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
SHARED_DIR="$SCRIPT_DIR/shared.d"
BASH_SPECIFIC_DIR="$SCRIPT_DIR/bash.d"
ZSH_SPECIFIC_DIR="$SCRIPT_DIR/zsh.d"

# -- help ---------------------------------------------------------------
# ----------------------------------------------------------------------
# usage — 输出 deploy.sh 的命令行帮助。
#
# 参数：无。
# 输出：stdout — 选项与示例。
# 返回码：echo 的退出码。
# ----------------------------------------------------------------------
usage() {
    echo -e "${BLUE}Usage:${NC} $SCRIPT_NAME [OPTIONS]"
    echo
    echo -e "自动同步 ${YELLOW}shell/shared.d/${NC} + shell 专属片段到 ${YELLOW}$CONFIG_DIR${NC}"
    echo -e "并确保 ${YELLOW}~/.bashrc${NC} 或 ${YELLOW}~/.zshrc${NC} 包含加载逻辑。"
    echo -e "同时在登录 profile（bash: ${YELLOW}~/.profile${NC}，zsh: ${YELLOW}~/.zprofile${NC}）"
    echo -e "维护 brew/fnm 受管环境块，供非交互登录 shell 使用。"
    echo
    echo -e "${BLUE}Options:${NC}"
    echo -e "  -h, --help              显示此帮助信息"
    echo -e "  -n, --dry-run           模拟执行，不进行实际写入"
    echo -e "  -s, --shell <bash|zsh>  指定目标 shell (默认: 自动检测)"
    echo -e "  -e, --exclude <pattern> 排除符合模式的文件 (可多次使用)"
    echo -e "                          例如: -e 'proxy.sh' -e 'test*.sh'"
    echo
    echo -e "${BLUE}Examples:${NC}"
    echo -e "  $SCRIPT_NAME                       # 正常同步 (自动检测 shell)"
    echo -e "  $SCRIPT_NAME --dry-run             # 仅查看会发生什么"
    echo -e "  $SCRIPT_NAME --shell zsh           # 强制按 Zsh 模式部署"
    echo -e "  $SCRIPT_NAME -e proxy.sh           # 同步但排除 proxy.sh"
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
log_err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }
# log_dry — 输出 dry-run 日志。
# 参数：$1 — 日志消息。
# 返回码：echo 的退出码。
log_dry()  { echo -e "${BLUE}[DRY]${NC}  $1" >&2; }

# -- functions ----------------------------------------------------------
# ----------------------------------------------------------------------
# detect_shell — 解析目标 shell，必要时回退到 Bash。
#
# 参数：无。
# 副作用：设置 SHELL_TYPE。
# 返回码：始终返回 0。
# ----------------------------------------------------------------------
detect_shell() {
    if [ -n "$SHELL_TYPE" ]; then
        return
    fi
    SHELL_TYPE=$(basename "${SHELL:-}")
    if [ "$SHELL_TYPE" != "bash" ] && [ "$SHELL_TYPE" != "zsh" ]; then
        log_warn "无法识别默认 shell '$SHELL_TYPE'，将使用 bash 模式"
        SHELL_TYPE="bash"
    fi
}

# ----------------------------------------------------------------------
# ensure_dir — 确保配置目录存在，或在 dry-run 中输出将执行的动作。
#
# 参数：无。
# 副作用：非 dry-run 时创建 CONFIG_DIR。
# 返回码：mkdir 或日志命令的退出码。
# ----------------------------------------------------------------------
ensure_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        if [ "$DRY_RUN" = true ]; then
             log_dry "创建目录: $CONFIG_DIR"
        else
             mkdir -p "$CONFIG_DIR"
             log_info "已创建配置目录: $CONFIG_DIR"
        fi
    fi
}

# ----------------------------------------------------------------------
# ensure_loader — 确保目标 rc 文件包含模块加载器，必要时创建备份。
#
# 参数：$1 — rc 文件路径；$2 — 文件不存在时是否创建。
# 副作用：可能创建 rc 文件、备份文件并追加加载器。
# 返回码：成功返回 0；文件操作失败时透传失败状态。
# ----------------------------------------------------------------------
ensure_loader() {
    local RC_FILE="$1"
    local CREATE_IF_MISSING="$2"
    local LOADER_MARK="# Load modular configuration files from ~/.bashrc.d"

    if [ ! -f "$RC_FILE" ]; then
        if [ "$CREATE_IF_MISSING" = true ]; then
            if [ "$DRY_RUN" = true ]; then
                log_dry "创建 $RC_FILE (因为不存在)"
                log_dry "向 $RC_FILE 添加加载逻辑"
                return 0
            else
                 touch "$RC_FILE"
                 log_info "已创建 $RC_FILE"
            fi
        else
            # 如果文件不存在且不强制创建，则跳过
            return 0
        fi
    fi

    if grep -Fq "$LOADER_MARK" "$RC_FILE"; then
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log_dry "向 $RC_FILE 添加加载逻辑"
        return
    fi

    log_info "检测到未配置加载器，正在向 $RC_FILE 添加加载逻辑..."

    if [ -s "$RC_FILE" ]; then
        local timestamp backup_path
        timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
        backup_path="${RC_FILE}.${timestamp}.bak"
        cp -p "$RC_FILE" "$backup_path"
        log_info "已备份现有配置: $backup_path"
    fi

    cat << 'EOF' >> "$RC_FILE"

# Load modular configuration files from ~/.bashrc.d
if [ -d "$HOME/.bashrc.d" ]; then
    for rc in "$HOME/.bashrc.d/"*.sh; do
        if [ -f "$rc" ]; then
            source "$rc"
        fi
    done
fi
EOF
    log_info "加载逻辑已添加至 $RC_FILE。"
}

# -- login profile ------------------------------------------------------
# 受管块 marker：整段替换的边界，用户内容必须放在 marker 之外。
LOGIN_MARKER_START='# >>> powershell-scripts login env >>>'
LOGIN_MARKER_END='# <<< powershell-scripts login env <<<'

# ----------------------------------------------------------------------
# ensure_login_profile — 维护登录 profile 中的 powershell-scripts 受管环境块。
#
# 设计意图：
#   非交互登录 shell（bash -lc、ssh 单命令、cron）不加载 ~/.bashrc.d 片段，
#   因此在登录 profile 写入自包含的 brew + fnm 恢复块；fnm 依赖 brew 恢复的
#   PATH，块内保持先 brew 后 fnm 的顺序。重复部署时 marker 之间的旧段整体
#   废弃并原位替换，marker 之外的用户内容逐行保留。
#
# 参数：无。
# 副作用：
#   非 dry-run 时创建登录 profile（bash: ~/.profile，zsh: ~/.zprofile），
#   原位替换 marker 之间的受管段，并在内容变化前生成时间戳 .bak 备份。
# 返回码：
#   0 — 已写入、已替换、已是最新或 dry-run。
#   非 0 — 临时文件、备份或写入失败。
# ----------------------------------------------------------------------
ensure_login_profile() {
    local profile_file
    if [ "$SHELL_TYPE" = "zsh" ]; then
        profile_file="$HOME/.zprofile"
    else
        profile_file="$HOME/.profile"
    fi

    local managed_block
    managed_block=$(cat <<'EOF'
# >>> powershell-scripts login env >>>
# 登录 profile 受管块：为非交互登录 shell（bash -lc、ssh、cron）恢复 Homebrew 与 fnm。
# 由 shell/deploy.sh 整段维护，请勿在 marker 之间手工修改。

# -- Homebrew -----------------------------------------------------------
# 候选顺序与 shell/shared.d/homebrew.sh 保持一致；PATH 去重保证重复加载幂等。
_powershell_scripts_brew_prefix=''
if [ -n "${POWERSHELL_SCRIPTS_HOMEBREW_PREFIX:-}" ] && [ -x "${POWERSHELL_SCRIPTS_HOMEBREW_PREFIX}/bin/brew" ]; then
    _powershell_scripts_brew_prefix="$POWERSHELL_SCRIPTS_HOMEBREW_PREFIX"
else
    for _powershell_scripts_brew_candidate in \
        /home/linuxbrew/.linuxbrew \
        "$HOME/.linuxbrew" \
        /opt/homebrew \
        /usr/local; do
        if [ -x "$_powershell_scripts_brew_candidate/bin/brew" ]; then
            _powershell_scripts_brew_prefix="$_powershell_scripts_brew_candidate"
            break
        fi
    done
fi

if [ -n "$_powershell_scripts_brew_prefix" ]; then
    export HOMEBREW_PREFIX="$_powershell_scripts_brew_prefix"
    export HOMEBREW_CELLAR="$_powershell_scripts_brew_prefix/Cellar"
    export HOMEBREW_REPOSITORY="$_powershell_scripts_brew_prefix/Homebrew"
    case ":$PATH:" in
        *":$_powershell_scripts_brew_prefix/bin:"*) ;;
        *) export PATH="$_powershell_scripts_brew_prefix/bin:$_powershell_scripts_brew_prefix/sbin:$PATH" ;;
    esac
fi
unset _powershell_scripts_brew_candidate _powershell_scripts_brew_prefix

# -- fnm ----------------------------------------------------------------
# 依赖上方 Homebrew 恢复的 PATH；default alias 由 fnm env 解析，不启用 --use-on-cd。
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env)"
fi
# <<< powershell-scripts login env <<<
EOF
)

    if [ "$DRY_RUN" = true ]; then
        if [ -f "$profile_file" ] && grep -Fq "$LOGIN_MARKER_START" "$profile_file"; then
            log_dry "替换 $profile_file 中的受管登录环境块"
        else
            log_dry "向 $profile_file 写入受管登录环境块"
        fi
        return 0
    fi

    if [ ! -f "$profile_file" ]; then
        printf '%s\n' "$managed_block" > "$profile_file" || return 1
        log_info "已创建 $profile_file 并写入受管登录环境块。"
        return 0
    fi

    # marker 之间的旧内容整体废弃，marker 之外的用户行原样保留；
    # 只有 start marker 而缺失 end marker 时，按“替换到文件尾”修复。
    local desired_file
    desired_file="$(mktemp "${TMPDIR:-/tmp}/powershell-scripts-login.XXXXXX")" || return 1

    POWERSHELL_SCRIPTS_LOGIN_BLOCK="$managed_block" \
    awk '
        $0 == "# >>> powershell-scripts login env >>>" {
            in_block = 1
            if (!replaced) {
                printf "%s\n", ENVIRON["POWERSHELL_SCRIPTS_LOGIN_BLOCK"]
                replaced = 1
            }
            next
        }
        in_block && $0 == "# <<< powershell-scripts login env <<<" {
            in_block = 0
            next
        }
        in_block { next }
        {
            print
            printed = 1
        }
        END {
            if (!replaced) {
                if (printed) printf "\n"
                printf "%s\n", ENVIRON["POWERSHELL_SCRIPTS_LOGIN_BLOCK"]
            }
        }
    ' "$profile_file" > "$desired_file" || { rm -f "$desired_file"; return 1; }

    # 内容已是最新时跳过，避免重复写入与多余备份。
    if cmp -s "$desired_file" "$profile_file"; then
        rm -f "$desired_file"
        log_info "$profile_file 中的受管登录环境块已是最新。"
        return 0
    fi

    if [ -s "$profile_file" ]; then
        local timestamp backup_path
        timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
        backup_path="${profile_file}.${timestamp}.bak"
        cp -p "$profile_file" "$backup_path" || { rm -f "$desired_file"; return 1; }
        log_info "已备份现有配置: $backup_path"
    fi

    cat "$desired_file" > "$profile_file" || { rm -f "$desired_file"; return 1; }
    rm -f "$desired_file"
    log_info "受管登录环境块已写入 $profile_file。"
}

# is_excluded — 判断文件名是否命中排除模式。
# 参数：$1 — 文件名。
# 返回码：命中返回 0，未命中返回 1。
is_excluded() {
    local filename="$1"
    if [ "$EXCLUDE_COUNT" -eq 0 ]; then
        return 1
    fi
    for pattern in "${EXCLUDE_LIST[@]}"; do
        # 使用 Bash [[ string == pattern ]] 保留 glob 模式匹配语义。
        if [[ "$filename" == $pattern ]]; then
            return 0 # true, excluded
        fi
    done
    return 1 # false, not excluded
}

# ----------------------------------------------------------------------
# cleanup_stale_symlinks — 清理配置目录中指向不存在路径的软链接。
#
# 参数：无。
# 副作用：非 dry-run 时删除失效软链接。
# 返回码：成功返回 0。
# ----------------------------------------------------------------------
cleanup_stale_symlinks() {
    if [ ! -d "$CONFIG_DIR" ]; then
        return
    fi

    local stale_count=0
    for link in "$CONFIG_DIR"/*; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then
            local target
            target=$(readlink "$link")
            if [ "$DRY_RUN" = true ]; then
                log_dry "删除失效 symlink: $(basename "$link") -> $target"
            else
                rm "$link"
                log_info "已删除失效 symlink: $(basename "$link") -> $target"
            fi
            stale_count=$((stale_count + 1))
        fi
    done

    if [ "$stale_count" -gt 0 ]; then
        log_info "清理了 $stale_count 个失效 symlink。"
    fi
}

# ----------------------------------------------------------------------
# sync_dir — 同步指定目录中的配置片段到 CONFIG_DIR。
#
# 参数：$1 — 源目录；$2 — 文件扩展名；$3 — 是否把 .zsh 重命名为 .sh。
# 输出：stdout — 已处理文件数量。
# 副作用：创建或更新配置片段软链接，并临时修改 nullglob 状态。
# 返回码：成功返回 0。
# ----------------------------------------------------------------------
sync_dir() {
    local source_dir="$1"
    local ext="$2"
    local rename_to_sh="$3"

    if [ ! -d "$source_dir" ]; then
        return 0
    fi

    shopt -s nullglob
    local count=0

    for file in "$source_dir"/*."$ext"; do
        if [ -f "$file" ]; then
            local filename
            filename=$(basename "$file")

            case "$filename" in
                *.example.sh|*.sample.sh)
                    log_info "跳过 (模板): $filename"
                    continue
                    ;;
            esac

            if is_excluded "$filename"; then
                log_info "跳过 (已排除): $filename"
                continue
            fi

            local target_name="$filename"
            if [ "$rename_to_sh" = true ]; then
                # 统一改用 .sh 后缀，使 ~/.bashrc.d/ loader 能加载 Zsh 专属片段。
                target_name="${filename%.zsh}.sh"
            fi
            local target_path="$CONFIG_DIR/$target_name"

            if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$file" ]; then
                log_info "软链接已是目标内容: $target_name"
            elif [ "$DRY_RUN" = true ]; then
                log_dry "创建软链接 $filename -> $target_path"
            else
                ln -sf "$file" "$target_path"
                log_info "已创建软链接: $filename -> $target_name"
            fi
            count=$((count + 1))
        fi
    done
    shopt -u nullglob

    echo "$count"
}

# ----------------------------------------------------------------------
# sync_snippets — 按目标 shell 同步 shared.d 与专属片段。
#
# 参数：无。
# 副作用：创建或更新配置片段软链接。
# 返回码：成功返回 0。
# ----------------------------------------------------------------------
sync_snippets() {
    log_info "开始同步配置片段 (shell: $SHELL_TYPE)..."
    if [ "$EXCLUDE_COUNT" -gt 0 ]; then
        echo -e "    ${YELLOW}排除列表: ${EXCLUDE_LIST[*]}${NC}" >&2
    fi

    local total=0

    # 先同步共享片段；源目录缺失时停止本次同步。
    if [ ! -d "$SHARED_DIR" ]; then
        log_warn "未找到源配置目录: $SHARED_DIR"
        return
    fi
    log_info "同步 shared.d/ (通用片段)..."
    local shared_count
    shared_count=$(sync_dir "$SHARED_DIR" "sh" false)
    total=$((total + shared_count))

    # 再按目标 shell 同步对应的专属片段。
    if [ "$SHELL_TYPE" = "zsh" ]; then
        if [ -d "$ZSH_SPECIFIC_DIR" ]; then
            log_info "同步 zsh.d/ (Zsh 专属片段)..."
            local zsh_count
            zsh_count=$(sync_dir "$ZSH_SPECIFIC_DIR" "zsh" true)
            total=$((total + zsh_count))
        fi
    else
        if [ -d "$BASH_SPECIFIC_DIR" ]; then
            log_info "同步 bash.d/ (Bash 专属片段)..."
            local bash_count
            bash_count=$(sync_dir "$BASH_SPECIFIC_DIR" "sh" false)
            total=$((total + bash_count))
        fi
    fi

    if [ "$total" -eq 0 ]; then
        if [ "$DRY_RUN" = true ]; then
             log_dry "没有文件会被同步。"
        else
             log_warn "没有文件被同步。"
        fi
    else
        log_info "同步完成，共处理 $total 个文件。"
    fi
}

# -- main ---------------------------------------------------------------
# 解析命令行参数后执行目录准备、旧链接清理、加载器维护和片段同步。
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--shell)
            if [[ -n "$2" && "$2" != -* ]]; then
                SHELL_TYPE="$2"
                if [ "$SHELL_TYPE" != "bash" ] && [ "$SHELL_TYPE" != "zsh" ]; then
                    log_err "--shell 参数仅支持 bash 或 zsh"
                    exit 2
                fi
                shift 2
            else
                log_err "参数 --shell 需要一个值 (bash 或 zsh)"
                exit 2
            fi
            ;;
        -e|--exclude)
            if [[ -n "$2" && "$2" != -* ]]; then
                EXCLUDE_LIST+=("$2")
                EXCLUDE_COUNT=$((EXCLUDE_COUNT + 1))
                shift 2
            else
                log_err "参数 --exclude 需要一个模式值"
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
log_info "检测到目标 shell: $SHELL_TYPE"

ensure_dir

cleanup_stale_symlinks

if [ "$SHELL_TYPE" = "zsh" ]; then
    ensure_loader "$HOME/.zshrc" true
    # 保持 Bash rc 在切换默认 shell 后仍可加载共享片段。
    ensure_loader "$HOME/.bashrc" false
else
    ensure_loader "$HOME/.bashrc" true
    # 保持 Zsh rc 在切换默认 shell 后仍可加载共享片段。
    ensure_loader "$HOME/.zshrc" false
fi

ensure_login_profile

sync_snippets
